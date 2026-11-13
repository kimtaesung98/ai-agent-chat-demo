package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"time"

	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/account"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/config"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/httpapi"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/store/sqlite"
	"github.com/kimtaesung98/ai-agent-chat-demo/server/internal/usage"
)

// 계정 기능 조립 (F-026·F-029·F-030): 저장소 → account·usage → httpapi.

// openAccounts는 DB를 열고 계정 기능 옵션을 만든다. 끝낼 때 close를 부른다.
// BOOTSTRAP_ADMIN_CODE가 있고 최고 관리자가 없으면 그 코드로 첫 최고 관리자를 만든다 (코드는 기록하지 않음).
func openAccounts(ctx context.Context, a config.Accounts, mock bool, log *slog.Logger) (httpapi.Option, func(), error) {
	db, err := sqlite.Open(a.DataDir)
	if err != nil {
		return nil, nil, fmt.Errorf("DB를 열 수 없어요: %w", err)
	}
	var opts []account.Option
	if a.GoogleClientID != "" {
		opts = append(opts, account.WithGoogle(&account.JWKSVerifier{ClientID: a.GoogleClientID}))
	}
	acc := account.New(db, opts...)
	lim := usage.New(db, usage.Limits{
		GuestTurns: a.GuestTurns, GuestPerIPHourly: a.GuestPerIPHourly, GuestDailyTotal: a.GuestDailyTotal,
		UserDailyTurns: a.UserDailyTurns, AdminDailyTurns: a.AdminDailyTurns, VoiceDailyMin: a.VoiceDailyMinutes,
		DailyGlobal: a.DailyGlobalLimit, CodeTriesPer10m: usage.Defaults.CodeTriesPer10m,
	}, nil)

	if a.BootstrapAdminCode != "" {
		switch _, _, err := acc.Bootstrap(ctx, a.BootstrapAdminName, a.BootstrapAdminCode); {
		case err == nil:
			log.Info("첫 최고 관리자를 만들었어요 (BOOTSTRAP_ADMIN_CODE로 로그인)")
		case errors.Is(err, account.ErrExists):
		case errors.Is(err, account.ErrInvalid):
			db.Close()
			return nil, nil, fmt.Errorf("BOOTSTRAP_ADMIN_CODE는 헷갈리는 글자(0·O·1·I)를 뺀 10자리여야 해요")
		default:
			db.Close()
			return nil, nil, err
		}
	}

	stop := make(chan struct{})
	go func() { // 끝난 세션·이틀 지난 사용량 지우기
		t := time.NewTicker(time.Hour)
		defer t.Stop()
		for {
			acc.Sweep(context.Background())
			lim.Sweep(context.Background())
			select {
			case <-stop:
				return
			case <-t.C:
			}
		}
	}()

	where := "메모리 DB — 다시 켜면 계정·데이터가 사라져요 (DATA_DIR로 파일 DB)"
	if a.DataDir != "" {
		where = "DATA_DIR의 chatd.db"
	}
	require := a.RequireLogin && !mock // 모의 모드는 언제나 열어 둔다 (테스트·시연)
	log.Info("계정: 켜짐", "store", where, "google", a.GoogleClientID != "", "guest", a.GuestMode, "care_setting", a.CareSetting, "ai_requires_session", require)
	if !mock && !a.RequireLogin {
		log.Warn("REQUIRE_LOGIN이 꺼져 있어 로그인 없이도 AI를 쓸 수 있어요 — 앱 로그인 화면이 나오면 켜 주세요 (F-030)")
	}

	opt := httpapi.WithAccounts(acc, lim, httpapi.AuthOptions{GuestMode: a.GuestMode, RequireSession: require, ClientIPHeader: a.ClientIPHeader, CareSetting: a.CareSetting})
	return opt, func() { close(stop); db.Close() }, nil
}

// adminCommand는 `chatd admin bootstrap -name 원장`이다 (F-026 AC7). 코드는 이 터미널에만 나온다.
func adminCommand(args []string, getenv func(string) string, out io.Writer) error {
	if len(args) == 0 || args[0] != "bootstrap" {
		return fmt.Errorf("쓰는 법: chatd admin bootstrap -name 이름   (DATA_DIR 필요)")
	}
	fs := flag.NewFlagSet("bootstrap", flag.ContinueOnError)
	fs.SetOutput(out)
	name := fs.String("name", "최고 관리자", "첫 최고 관리자 이름 (20자까지)")
	if err := fs.Parse(args[1:]); err != nil {
		return err
	}
	a, err := config.LoadAccounts(getenv)
	if err != nil {
		return err
	}
	if a.DataDir == "" {
		return fmt.Errorf("DATA_DIR를 정해 주세요 — 메모리 DB에 만들면 명령이 끝날 때 사라져요")
	}
	if err := os.MkdirAll(a.DataDir, 0o700); err != nil {
		return err
	}
	db, err := sqlite.Open(a.DataDir)
	if err != nil {
		return err
	}
	defer db.Close()
	u, code, err := account.New(db).Bootstrap(context.Background(), *name, "")
	if errors.Is(err, account.ErrExists) {
		return fmt.Errorf("이미 최고 관리자가 있어요 — 코드는 관리 화면에서 다시 만들어요")
	} else if err != nil {
		return err
	}
	fmt.Fprintf(out, "최고 관리자 계정(%s)을 만들었어요.\n로그인 코드: %s\n(%s까지, 한 번만 쓸 수 있어요. 다른 곳에 적어 두지 마세요.)\n", u.Name, code, time.Now().Add(account.CodeTTL).Format("2006-01-02 15:04"))
	return nil
}
