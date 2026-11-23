package merge

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"errors"
	"io/fs"
	"os"
	"path/filepath"

	"github.com/arbourd/dotfiles/internal/env"
	"github.com/arbourd/dotfiles/internal/ui"
)

// Orca merges settings into Orca's profile database and updates content_hash.
func Orca(ctx context.Context, u *ui.UI) error {
	db := filepath.Join(u.Env.Home, "Library", "Application Support", "orca", "profiles", "local-default", "profile-state.db")
	if _, err := os.Stat(db); errors.Is(err, fs.ErrNotExist) {
		u.Status(ui.Skipped, "orca settings: "+db+" not found")
		return nil
	}

	if u.Env.TermProgram == "Orca" {
		u.Status(ui.Skipped, "orca settings: run from a terminal outside Orca")
		return nil
	}
	if u.Env.Runner.Run(ctx, env.Cmd{Name: "pgrep", Args: []string{"-x", "Orca"}}) == nil {
		u.Status(ui.Skipped, "orca settings: quit Orca and rerun")
		return nil
	}

	errNoPayload := errors.New("Error: orca settings merge produced no payload (settings.jsonc missing, or no settings row)")
	repo, err := os.ReadFile(filepath.Join(u.Dir, "orca", "settings.jsonc"))
	if errors.Is(err, fs.ErrNotExist) {
		return errNoPayload
	}
	if err != nil {
		return err
	}

	conn, err := openDB(db)
	if err != nil {
		return err
	}
	defer conn.Close()

	// RFC 7396 merge patch: nested objects merge, null deletes a key.
	tx, err := conn.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var payload sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT json_patch(payload, json(?)) FROM profile_state_documents WHERE domain='settings'`, string(repo)).Scan(&payload)
	if errors.Is(err, sql.ErrNoRows) || (err == nil && payload.String == "") {
		return errNoPayload
	}
	if err != nil {
		return err
	}

	sum := sha256.Sum256([]byte(payload.String))
	if _, err := tx.ExecContext(ctx, `UPDATE profile_state_documents SET payload = ?, content_hash = ? WHERE domain='settings'`, payload.String, hex.EncodeToString(sum[:])); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}

	u.Status(ui.Merged, "orca settings → "+db)
	return nil
}
