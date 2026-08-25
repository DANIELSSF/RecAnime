package httpapi

import (
	"fmt"
	"net/http"
	"time"

	"github.com/danielssf/recanime/services/api/internal/model"
	"github.com/danielssf/recanime/services/api/internal/store"
)

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	p := mustPrincipal(r)
	u, err := s.deps.Store.GetUser(r.Context(), p.UserID)
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, userDTO(u), nil, nil)
}

type settingsPatch struct {
	SFW      *bool   `json:"sfw"`
	Timezone *string `json:"timezone"`
}

func (s *Server) handlePatchSettings(w http.ResponseWriter, r *http.Request) {
	p := mustPrincipal(r)
	var body settingsPatch
	if err := decodeJSON(r, &body); err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	if body.SFW == nil && body.Timezone == nil {
		s.writeServiceError(w, r, fmt.Errorf("%w: nothing to update", errValidation))
		return
	}
	if body.Timezone != nil {
		if _, err := time.LoadLocation(*body.Timezone); err != nil || *body.Timezone == "" {
			s.writeServiceError(w, r, fmt.Errorf("%w: timezone must be an IANA name", errValidation))
			return
		}
	}
	st, err := s.deps.Store.UpdateSettings(r.Context(), p.UserID, store.SettingsPatch{SFW: body.SFW, Timezone: body.Timezone})
	if err != nil {
		s.writeServiceError(w, r, err)
		return
	}
	writeData(w, http.StatusOK, model.Settings{SFW: st.SFW, Timezone: st.Timezone}, nil, nil)
}

func userDTO(u store.User) model.User {
	return model.User{
		ID: u.ID, Email: u.Email, DisplayName: u.DisplayName, AvatarURL: u.AvatarURL, CreatedAt: u.CreatedAt,
		Settings: model.Settings{SFW: u.Settings.SFW, Timezone: u.Settings.Timezone},
	}
}

// sfwFor returns the caller's SFW preference (default true when settings are missing).
func (s *Server) sfwFor(r *http.Request) bool {
	p := mustPrincipal(r)
	st, err := s.deps.Store.GetSettings(r.Context(), p.UserID)
	if err != nil {
		return true
	}
	return st.SFW
}
