package httpapi

import (
	"log/slog"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/danielssf/recanime/services/api/internal/anime"
	"github.com/danielssf/recanime/services/api/internal/catalog"
	"github.com/danielssf/recanime/services/api/internal/library"
	"github.com/danielssf/recanime/services/api/internal/schedule"
	"github.com/danielssf/recanime/services/api/internal/store"
)

// Deps are the collaborators the HTTP layer needs.
type Deps struct {
	Logger  *slog.Logger
	Pool    *pgxpool.Pool
	Version string

	Store    *store.Store
	Anime    *anime.Service
	Catalog  *catalog.Service
	Library  *library.Service
	Schedule *schedule.Service

	Auth            AuthConfig
	FranchiseBudget int
}

// Server holds the router and its dependencies.
type Server struct {
	deps    Deps
	router  chi.Router
	ensurer *userEnsurer
}

// New builds the router with the full middleware chain.
func New(deps Deps) *Server {
	s := &Server{deps: deps, ensurer: &userEnsurer{seen: map[string]time.Time{}}}
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(requestLogger(deps.Logger))
	r.Use(middleware.Recoverer)
	r.Use(middleware.Compress(5, "application/json")) // list payloads shrink ~5x over cellular
	r.Use(middleware.Timeout(25 * time.Second))
	r.Use(maxBodyBytes(64 << 10))

	r.Get("/healthz", s.handleHealthz)
	r.Get("/readyz", s.handleReadyz)

	r.Route("/v1", func(v1 chi.Router) {
		v1.Use(s.authenticate)
		s.mountV1(v1)
	})

	r.NotFound(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, r, http.StatusNotFound, "not_found", "route not found")
	})
	r.MethodNotAllowed(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, r, http.StatusMethodNotAllowed, "method_not_allowed", "method not allowed")
	})
	s.router = r
	return s
}

// mountV1 registers the authenticated API.
func (s *Server) mountV1(r chi.Router) {
	r.Get("/me", s.handleMe)
	r.Patch("/me/settings", s.handlePatchSettings)

	r.Get("/anime/{id}", s.handleAnimeDetail)
	r.Get("/anime/{id}/franchise", s.handleFranchise)
	r.Get("/anime/{id}/episodes", s.handleEpisodes)
	r.Get("/anime/{id}/recommendations", s.handleAnimeRecommendations)

	r.Get("/seasons", s.handleSeasonsIndex)
	r.Get("/seasons/now", s.handleSeasonNow)
	r.Get("/seasons/upcoming", s.handleSeasonUpcoming)
	r.Get("/seasons/{year}/{season}", s.handleSeason)
	r.Get("/top", s.handleTop)
	r.Get("/recommendations", s.handleRecommendations)
	r.Get("/search", s.handleSearch)
	r.Get("/schedules", s.handleSchedules)

	r.Get("/me/library", s.handleLibraryList)
	r.Put("/me/library/batch", s.handleLibraryBatch)
	r.Get("/me/library/{malId}", s.handleLibraryGet)
	r.Put("/me/library/{malId}", s.handleLibraryPut)
	r.Post("/me/library/{malId}/episodes", s.handleLibraryEpisodes)
	r.Delete("/me/library/{malId}", s.handleLibraryDelete)
	r.Get("/me/schedule", s.handleSchedule)
}

// ServeHTTP makes Server an http.Handler.
func (s *Server) ServeHTTP(w http.ResponseWriter, r *http.Request) { s.router.ServeHTTP(w, r) }
