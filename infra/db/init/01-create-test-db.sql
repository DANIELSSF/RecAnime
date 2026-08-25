-- Runs once when the Docker volume is first initialized.
-- Creates the database used by the Go integration tests (pnpm api:test:it).
CREATE DATABASE recanime_test;
