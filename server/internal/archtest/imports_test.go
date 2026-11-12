package archtest

import (
	"go/parser"
	"go/token"
	"io/fs"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"
)

const module = "github.com/kimtaesung98/ai-agent-chat-demo/server"
const sdk = "github.com/anthropics/anthropic-sdk-go"

// allowed는 패키지(module 기준 상대 경로)마다 import해도 되는 모듈 내부 패키지다.
// 여기 없는 패키지는 검사에 실패한다 → 새 패키지를 만들면 ARCHITECTURE.md §3.2·§3.3과 이 표를 같이 고친다.
var allowed = map[string][]string{
	"cmd/chatd":                   {"internal/config", "internal/httpapi", "internal/provider", "internal/provider/anthropic", "internal/provider/mock", "internal/elevenlabs"},
	"contract":                    {},
	"internal/archtest":           {},
	"internal/chat":               {},
	"internal/config":             {},
	"internal/elevenlabs":         {},
	"internal/provider":           {"internal/chat"},
	"internal/provider/mock":      {"internal/chat", "internal/provider"},
	"internal/provider/anthropic": {"internal/chat", "internal/provider"},
	"internal/httpapi":            {"internal/chat", "internal/provider"},
}

func TestImportRules(t *testing.T) {
	root, _ := filepath.Abs("../..")
	imports := map[string][]string{} // 패키지 → import 목록 (테스트 파일 제외)
	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return err
		}
		f, err := parser.ParseFile(token.NewFileSet(), path, nil, parser.ImportsOnly)
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, filepath.Dir(path))
		rel = filepath.ToSlash(rel)
		imports[rel] = append(imports[rel], "") // 파일이 있는 패키지 표시
		for _, im := range f.Imports {
			p, _ := strconv.Unquote(im.Path.Value)
			imports[rel] = append(imports[rel], p)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	t.Run("F-010 AC6 모든 패키지가 모듈 맵에 있고 허용된 내부 패키지만 import한다", func(t *testing.T) {
		for pkg, list := range imports {
			rules, ok := allowed[pkg]
			if !ok {
				t.Errorf("%s: 모듈 맵에 없는 패키지예요 (ARCHITECTURE.md §3.2)", pkg)
				continue
			}
			for _, p := range list {
				if inner, ok := strings.CutPrefix(p, module+"/"); ok && !slices.Contains(rules, inner) {
					t.Errorf("%s → %s: 의존 규칙 위반 (ARCHITECTURE.md §3.3)", pkg, inner)
				}
			}
		}
	})

	t.Run("F-010 AC6 Anthropic SDK는 provider/anthropic에서만 import한다", func(t *testing.T) {
		for pkg, list := range imports {
			for _, p := range list {
				if strings.HasPrefix(p, sdk) && pkg != "internal/provider/anthropic" {
					t.Errorf("%s가 SDK(%s)를 import해요 (ADR-008)", pkg, p)
				}
			}
		}
	})

	t.Run("F-010 AC6 cgo를 쓰지 않는다", func(t *testing.T) {
		for pkg, list := range imports {
			if slices.Contains(list, "C") {
				t.Errorf("%s가 cgo를 써요 (ADR-007)", pkg)
			}
		}
	})

	t.Run("F-009 계약 테스트와 chat 도메인은 표준 라이브러리만 쓴다", func(t *testing.T) {
		for _, pkg := range []string{"contract", "internal/chat", "internal/config", "internal/elevenlabs"} {
			for _, p := range imports[pkg] {
				if first, _, _ := strings.Cut(p, "/"); strings.Contains(first, ".") {
					t.Errorf("%s가 외부 모듈 %s를 import해요", pkg, p)
				}
			}
		}
	})
}
