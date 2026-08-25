package httpapi

import (
	"fmt"
	"net/http"

	"github.com/danielssf/recanime/services/api/internal/library"
)

func (s *Server) handleLibraryList(w http.ResponseWriter, r *http.Request) {
	p := mustPrincipal(r)
	status := queryStringPtr(r, "status")
	favorite, err := queryBoolPtr(r, "favorite")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	if status == nil && favorite == nil {
		groups, err := s.deps.Library.Grouped(r.Context(), p.UserID)
		if err != nil {
			s.writeServiceError(w, r, err)
			return
		}
		writeData(w, http.StatusOK, groups, nil, nil)
		return
	}
	items, err := s.deps.Library.List(r.Context(), p.UserID, status, favorite)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, items, nil, nil)
}

func (s *Server) handleLibraryGet(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "malId")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	item, err := s.deps.Library.Get(r.Context(), mustPrincipal(r).UserID, id)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, item, nil, nil)
}

type libraryPatchBody struct {
	Status          *string `json:"status"`
	Favorite        *bool   `json:"favorite"`
	EpisodesWatched *int    `json:"episodesWatched"`
}

func (s *Server) handleLibraryPut(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "malId")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	var body libraryPatchBody
	if err := decodeJSON(r, &body); err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	item, err := s.deps.Library.Upsert(r.Context(), mustPrincipal(r).UserID, id, library.Patch{Status: body.Status, Favorite: body.Favorite, EpisodesWatched: body.EpisodesWatched})
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, item, nil, nil)
}

type batchBody struct {
	Items []struct {
		MalID           int     `json:"malId"`
		Status          *string `json:"status"`
		Favorite        *bool   `json:"favorite"`
		EpisodesWatched *int    `json:"episodesWatched"`
	} `json:"items"`
}

// handleLibraryBatch applies several library changes in one transaction.
func (s *Server) handleLibraryBatch(w http.ResponseWriter, r *http.Request) {
	var body batchBody
	if err := decodeJSON(r, &body); err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	items := make([]library.BatchItem, 0, len(body.Items))
	for _, it := range body.Items {
		if it.MalID <= 0 {
			s.writeServiceError(w, r, fmt.Errorf("%w: malId must be a positive integer", errValidation))
			return
		}
		items = append(items, library.BatchItem{MalID: it.MalID, Patch: library.Patch{Status: it.Status, Favorite: it.Favorite, EpisodesWatched: it.EpisodesWatched}})
	}
	result, err := s.deps.Library.Batch(r.Context(), mustPrincipal(r).UserID, items)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, result, nil, nil)
}

type episodesBody struct {
	EpisodesWatched *int `json:"episodesWatched"`
	Delta           *int `json:"delta"`
}

func (s *Server) handleLibraryEpisodes(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "malId")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	var body episodesBody
	if err := decodeJSON(r, &body); err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	item, err := s.deps.Library.AdjustEpisodes(r.Context(), mustPrincipal(r).UserID, id, body.EpisodesWatched, body.Delta)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, item, nil, nil)
}

func (s *Server) handleLibraryDelete(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "malId")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	if err := s.deps.Library.Delete(r.Context(), mustPrincipal(r).UserID, id); err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleSchedule(w http.ResponseWriter, r *http.Request) {
	include, err := queryBoolPtr(r, "includeEpisodes")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	res, err := s.deps.Schedule.ForUser(r.Context(), mustPrincipal(r).UserID, include != nil && *include)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, res.Items, &Meta{Stale: res.Stale}, nil)
}
