package httpapi

import (
	"net/http"
)

func (s *Server) handleAnimeDetail(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "id")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	p := mustPrincipal(r)
	detail, res, err := s.deps.Anime.Detail(r.Context(), p.UserID, id)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, detail, metaFor(res.Status, res.FetchedAt, res.UpstreamErr), nil)
}

func (s *Server) handleFranchise(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "id")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	budget, err := queryInt(r, "budget", s.deps.FranchiseBudget)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	if budget > s.deps.FranchiseBudget {
		budget = s.deps.FranchiseBudget
	}
	p := mustPrincipal(r)
	fr, err := s.deps.Anime.Franchise(r.Context(), p.UserID, id, budget)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, fr, nil, nil)
}

func (s *Server) handleEpisodes(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "id")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	page, err := queryPage(r)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	eps, pg, res, err := s.deps.Catalog.Episodes(r.Context(), id, page)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, eps, metaFor(res.Status, res.FetchedAt, res.UpstreamErr), &pg)
}

func (s *Server) handleAnimeRecommendations(w http.ResponseWriter, r *http.Request) {
	id, err := pathInt(r, "id")
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	p := mustPrincipal(r)
	recs, res, err := s.deps.Catalog.AnimeRecommendations(r.Context(), p.UserID, s.sfwFor(r), id)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, recs, metaFor(res.Status, res.FetchedAt, res.UpstreamErr), nil)
}
