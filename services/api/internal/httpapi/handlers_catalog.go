package httpapi

import (
	"net/http"
	"strings"

	"github.com/go-chi/chi/v5"

	"github.com/danielssf/recanime/services/api/internal/catalog"
)

func (s *Server) listParams(r *http.Request) (catalog.ListParams, error) {
	page, err := queryInt(r, "page", 1)
	if err != nil {
		return catalog.ListParams{}, err
	}
	q := r.URL.Query()
	return catalog.ListParams{
		Filter: strings.ToLower(strings.TrimSpace(q.Get("filter"))),
		Type:   strings.ToLower(strings.TrimSpace(q.Get("type"))),
		Rating: strings.ToLower(strings.TrimSpace(q.Get("rating"))),
		Page:   page,
	}, nil
}

func (s *Server) writePage(w http.ResponseWriter, pg catalog.Page) {
	m := pg.Meta
	writeData(w, http.StatusOK, pg.Items, metaFor(m.Status, m.FetchedAt, m.UpstreamErr), &pg.Pagination)
}

func (s *Server) handleTop(w http.ResponseWriter, r *http.Request) {
	params, err := s.listParams(r)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	pg, err := s.deps.Catalog.Top(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), params)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleSeasonNow(w http.ResponseWriter, r *http.Request) {
	params, err := s.listParams(r)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	pg, err := s.deps.Catalog.SeasonNow(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), params)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleSeasonUpcoming(w http.ResponseWriter, r *http.Request) {
	params, err := s.listParams(r)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	pg, err := s.deps.Catalog.SeasonUpcoming(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), params)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleSeason(w http.ResponseWriter, r *http.Request) {
	year, err := pathInt(r, "year")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	params, err := s.listParams(r)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	pg, err := s.deps.Catalog.Season(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), year, chi.URLParam(r, "season"), params)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleSeasonsIndex(w http.ResponseWriter, r *http.Request) {
	idx, res, err := s.deps.Catalog.SeasonsIndex(r.Context())
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, idx, metaFor(res.Status, res.FetchedAt, res.UpstreamErr), nil)
}

func (s *Server) handleSchedules(w http.ResponseWriter, r *http.Request) {
	page, err := queryInt(r, "page", 1)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	pg, err := s.deps.Catalog.Schedules(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), r.URL.Query().Get("day"), page)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleSearch(w http.ResponseWriter, r *http.Request) {
	page, err := queryInt(r, "page", 1)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	q := r.URL.Query()
	params := catalog.SearchParams{
		Q:        q.Get("q"),
		Type:     strings.ToLower(strings.TrimSpace(q.Get("type"))),
		Status:   strings.ToLower(strings.TrimSpace(q.Get("status"))),
		OrderBy:  strings.ToLower(strings.TrimSpace(q.Get("orderBy"))),
		Sort:     strings.ToLower(strings.TrimSpace(q.Get("sort"))),
		Genres:   strings.TrimSpace(q.Get("genres")),
		MinScore: strings.TrimSpace(q.Get("minScore")),
		Page:     page,
	}
	pg, err := s.deps.Catalog.Search(r.Context(), mustPrincipal(r).UserID, s.sfwFor(r), params)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	s.writePage(w, pg)
}

func (s *Server) handleRecommendations(w http.ResponseWriter, r *http.Request) {
	page, err := queryInt(r, "page", 1)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	recs, pg, status, err := s.deps.Catalog.LiveRecommendations(r.Context(), mustPrincipal(r).UserID, page)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, recs, &Meta{Cache: string(status), Stale: status == "STALE"}, &pg)
}
