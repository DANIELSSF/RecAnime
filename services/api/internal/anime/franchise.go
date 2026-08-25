package anime

import (
	"context"
	"sort"
	"strings"

	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

const maxHops = 20

// Franchise walks Prequel/Sequel relations around rootID and overlays the user's progress.
// budget bounds how many uncached entries may be fetched from Jikan during the walk.
func (s *Service) Franchise(ctx context.Context, userID string, rootID int, budget int) (model.Franchise, error) {
	w := &walker{s: s, ctx: ctx, budget: budget, rows: map[int]store.AnimeRow{}, rels: map[int][]store.RelationRow{}, visited: map[int]bool{rootID: true}}

	root, err := s.Ensure(ctx, rootID)
	if err != nil {
		return model.Franchise{}, err
	}
	w.rows[rootID] = root

	back, backComplete := w.walk(rootID, "Prequel")
	fwd, fwdComplete := w.walk(rootID, "Sequel")

	// Prequels come back nearest-first; reverse so the chain reads oldest → newest.
	for i, j := 0, len(back)-1; i < j; i, j = i+1, j-1 {
		back[i], back[j] = back[j], back[i]
	}
	chain := append(append(back, chainNode{id: rootID, name: root.Title}), fwd...)

	ids := make([]int, 0, len(chain))
	for _, n := range chain {
		ids = append(ids, n.id)
	}
	overlays, err := s.store.LibraryEntriesFor(ctx, userID, ids)
	if err != nil {
		return model.Franchise{}, err
	}

	fr := model.Franchise{Complete: backComplete && fwdComplete, Entries: make([]model.FranchiseEntry, 0, len(chain))}
	requested, watching, lastWatched := 0, -1, -1
	for i, n := range chain {
		entry := model.FranchiseEntry{MalID: n.id, Title: n.name, Position: i + 1, RelationToPrevious: n.relation}
		if row, ok := w.rows[n.id]; ok {
			sum := SummaryFromRow(row)
			if e, has := overlays[n.id]; has {
				sum.Library = OverlayFromEntry(e)
				switch e.Status {
				case store.StatusWatching:
					if watching == -1 {
						watching = i
					}
				case store.StatusWatched:
					lastWatched = i
				}
			}
			entry.Resolved = true
			entry.Title = row.Title
			entry.Anime = &sum
		}
		if n.id == rootID {
			requested = i
		}
		fr.Entries = append(fr.Entries, entry)
	}
	fr.RequestedIndex = requested
	switch {
	case watching >= 0:
		fr.CurrentIndex = watching
	case lastWatched >= 0:
		fr.CurrentIndex = lastWatched
	default:
		fr.CurrentIndex = requested
	}
	if fr.CurrentIndex+1 < len(fr.Entries) {
		next := fr.Entries[fr.CurrentIndex+1]
		fr.NextSeason = &next
	}
	fr.SideEntries = w.sideEntries(ids)
	return fr, nil
}

type chainNode struct {
	id       int
	name     string
	relation string // relation from the previous node in reading order
}

type walker struct {
	s       *Service
	ctx     context.Context
	budget  int
	rows    map[int]store.AnimeRow
	rels    map[int][]store.RelationRow
	visited map[int]bool
}

// walk follows `kind` relations (Sequel or Prequel) from id, nearest first.
// The second result is false when the chain was cut short (unresolved stub or hop cap).
func (w *walker) walk(id int, kind string) ([]chainNode, bool) {
	var out []chainNode
	current := id
	for hop := 0; hop < maxHops; hop++ {
		rels, ok := w.relations(current)
		if !ok {
			return out, false
		}
		var cands []store.RelationRow
		for _, r := range rels {
			if strings.EqualFold(r.Relation, kind) && r.ToType == "anime" && !w.visited[r.ToMalID] {
				cands = append(cands, r)
			}
		}
		if len(cands) == 0 {
			return out, true
		}
		next := w.pickMain(cands, w.rows[current], kind)
		w.visited[next.ToMalID] = true
		node := chainNode{id: next.ToMalID, name: next.ToName, relation: kind}
		if _, ok := w.rows[next.ToMalID]; !ok {
			if !w.fetch(next.ToMalID) {
				// Unresolved stub: relations of an uncached anime are unknown, stop here.
				out = append(out, node)
				return out, false
			}
		}
		node.name = w.rows[next.ToMalID].Title
		out = append(out, node)
		current = next.ToMalID
	}
	return out, false
}

// fetch downloads an uncached anime when the budget allows and records its row.
func (w *walker) fetch(id int) bool {
	if w.budget <= 0 {
		return false
	}
	w.budget--
	res, err := w.s.Get(w.ctx, id)
	if err != nil {
		return false
	}
	w.rows[id] = res.Value
	return true
}

// relations returns the cached relations of id (the row must already be known or cached).
func (w *walker) relations(id int) ([]store.RelationRow, bool) {
	if rels, ok := w.rels[id]; ok {
		return rels, true
	}
	if _, cached := w.rows[id]; !cached {
		row, found, err := w.s.store.GetAnime(w.ctx, id)
		if err != nil || !found {
			return nil, false
		}
		w.rows[id] = row
	}
	rels, err := w.s.store.GetRelations(w.ctx, id)
	if err != nil {
		return nil, false
	}
	w.rels[id] = rels
	// Pre-load candidate rows so pickMain can compare types/dates.
	var missing []int
	for _, r := range rels {
		if r.ToType == "anime" {
			if _, ok := w.rows[r.ToMalID]; !ok {
				missing = append(missing, r.ToMalID)
			}
		}
	}
	if len(missing) > 0 {
		if batch, err := w.s.store.GetAnimeBatch(w.ctx, missing); err == nil {
			for id, row := range batch {
				w.rows[id] = row
			}
		}
	}
	return rels, true
}

// pickMain chooses the main-line continuation among several candidates:
// same type as the current entry first, then air date (earliest for sequels, latest for
// prequels), then the lowest MAL id for determinism.
func (w *walker) pickMain(cands []store.RelationRow, current store.AnimeRow, kind string) store.RelationRow {
	if len(cands) == 1 {
		return cands[0]
	}
	sort.SliceStable(cands, func(i, j int) bool {
		ri, iok := w.rows[cands[i].ToMalID]
		rj, jok := w.rows[cands[j].ToMalID]
		si, sj := sameType(current, ri, iok), sameType(current, rj, jok)
		if si != sj {
			return si
		}
		if iok && jok && ri.AiredFrom != nil && rj.AiredFrom != nil && !ri.AiredFrom.Equal(*rj.AiredFrom) {
			if kind == "Prequel" {
				return ri.AiredFrom.After(*rj.AiredFrom)
			}
			return ri.AiredFrom.Before(*rj.AiredFrom)
		}
		if iok != jok {
			return iok
		}
		return cands[i].ToMalID < cands[j].ToMalID
	})
	return cands[0]
}

func sameType(current, other store.AnimeRow, ok bool) bool {
	return ok && current.Type != nil && other.Type != nil && *current.Type == *other.Type
}

// sideEntries lists related anime that are not part of the main chain.
func (w *walker) sideEntries(chain []int) []model.SideEntry {
	inChain := map[int]bool{}
	for _, id := range chain {
		inChain[id] = true
	}
	seen := map[int]bool{}
	var out []model.SideEntry
	for _, id := range chain {
		for _, r := range w.rels[id] {
			if r.ToType != "anime" || inChain[r.ToMalID] || seen[r.ToMalID] {
				continue
			}
			if strings.EqualFold(r.Relation, "Sequel") || strings.EqualFold(r.Relation, "Prequel") {
				continue
			}
			seen[r.ToMalID] = true
			out = append(out, model.SideEntry{Relation: r.Relation, MalID: r.ToMalID, Name: r.ToName})
		}
	}
	if out == nil {
		out = []model.SideEntry{}
	}
	return out
}
