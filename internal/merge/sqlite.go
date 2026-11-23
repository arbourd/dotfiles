package merge

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite" // registers the pure-Go "sqlite" driver
)

// jsonPatchSQL uses SQLite json_patch to match the claude-settings-audit skill.
// json() accepts JSONC comments and trailing commas; blank live files count as {}.
const jsonPatchSQL = `SELECT json_patch(
	json(coalesce(nullif(trim(?, ' '||char(9,10,13)), ''), '{}')),
	json(?))`

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	return db, nil
}

// JSONPatch applies repo over live as an RFC 7396 merge patch and returns compact JSON.
// Nil or blank live input is {}; both inputs may be JSONC. An empty result means SQLite returned NULL.
func JSONPatch(ctx context.Context, live, repo []byte) ([]byte, error) {
	db, err := openDB(":memory:")
	if err != nil {
		return nil, err
	}
	defer db.Close()

	var out sql.NullString
	if err := db.QueryRowContext(ctx, jsonPatchSQL, string(live), string(repo)).Scan(&out); err != nil {
		return nil, fmt.Errorf("json_patch: %w", err)
	}
	return []byte(out.String), nil
}
