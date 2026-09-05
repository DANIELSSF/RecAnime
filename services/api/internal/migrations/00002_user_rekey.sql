-- +goose Up
-- A recreated Supabase project (or a user deleted and added again) issues a new `sub` for the
-- same email. store.UpsertUser re-keys the existing app_user row instead of tripping
-- app_user_email_lower_uidx, so the child rows have to follow the new id.
ALTER TABLE recanime.library_entry
  DROP CONSTRAINT library_entry_user_id_fkey,
  ADD CONSTRAINT library_entry_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES recanime.app_user(id) ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE recanime.user_settings
  DROP CONSTRAINT user_settings_user_id_fkey,
  ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES recanime.app_user(id) ON DELETE CASCADE ON UPDATE CASCADE;

-- +goose Down
ALTER TABLE recanime.library_entry
  DROP CONSTRAINT library_entry_user_id_fkey,
  ADD CONSTRAINT library_entry_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES recanime.app_user(id) ON DELETE CASCADE;

ALTER TABLE recanime.user_settings
  DROP CONSTRAINT user_settings_user_id_fkey,
  ADD CONSTRAINT user_settings_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES recanime.app_user(id) ON DELETE CASCADE;
