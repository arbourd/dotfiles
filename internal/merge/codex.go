package merge

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/arbourd/dotfiles/internal/paths"
	"github.com/arbourd/dotfiles/internal/ui"
	"github.com/pelletier/go-toml/v2"
)

// Codex merges agents/codex/config.toml into ~/.codex/config.toml.
func Codex(_ context.Context, u *ui.UI) error {
	live := filepath.Join(u.Env.Home, ".codex", "config.toml")
	repo := filepath.Join(u.Dir, "agents", "codex", "config.toml")
	if err := paths.Ensure(live, 0); err != nil {
		return err
	}

	liveData, err := os.ReadFile(live)
	if err != nil {
		return fmt.Errorf("read %s: %w", live, err)
	}
	repoData, err := os.ReadFile(repo)
	if err != nil {
		return fmt.Errorf("read %s: %w", repo, err)
	}

	var merged map[string]any
	if err := toml.Unmarshal(liveData, &merged); err != nil {
		return fmt.Errorf("decode %s: %w", live, err)
	}
	if merged == nil {
		merged = make(map[string]any)
	}
	var repoMap map[string]any
	if err := toml.Unmarshal(repoData, &repoMap); err != nil {
		return fmt.Errorf("decode %s: %w", repo, err)
	}
	deepMerge(merged, repoMap)

	output, err := toml.Marshal(merged)
	if err != nil {
		return fmt.Errorf("encode %s: %w", live, err)
	}
	tmp, err := os.CreateTemp(filepath.Dir(live), ".config.toml-*")
	if err != nil {
		return fmt.Errorf("create temp config: %w", err)
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(output); err != nil {
		tmp.Close()
		return fmt.Errorf("write temp config: %w", err)
	}
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return fmt.Errorf("chmod temp config: %w", err)
	}
	if err := tmp.Close(); err != nil {
		return fmt.Errorf("close temp config: %w", err)
	}
	if err := os.Rename(tmpName, live); err != nil {
		return fmt.Errorf("replace %s: %w", live, err)
	}
	u.Status(ui.Merged, fmt.Sprintf("%s → %s", repo, live))
	return nil
}

func deepMerge(dst, src map[string]any) {
	for key, value := range src {
		if srcMap, ok := value.(map[string]any); ok {
			if dstMap, ok := dst[key].(map[string]any); ok {
				deepMerge(dstMap, srcMap)
				continue
			}
		}
		dst[key] = value
	}
}
