package config

import "testing"

func TestF030LoadAccounts(t *testing.T) {
	env := func(m map[string]string) func(string) string { return func(k string) string { return m[k] } }
	a, err := LoadAccounts(env(nil))
	if err != nil || a.GuestMode || a.GuestTurns != 10 || a.DailyGlobalLimit != 5000 || a.CareSetting != "daycare" || a.DataDir != "" {
		t.Fatalf("F-030 기본값: %+v %v", a, err)
	}
	a, err = LoadAccounts(env(map[string]string{"GUEST_MODE": "on", "GUEST_TURNS": "5", "DATA_DIR": "/data", "REQUIRE_LOGIN": "on"}))
	if err != nil || !a.RequireLogin || !a.GuestMode || a.GuestTurns != 5 || a.DataDir != "/data" {
		t.Fatalf("값 읽기: %+v %v", a, err)
	}
	for k, v := range map[string]string{"GUEST_MODE": "maybe", "GUEST_TURNS": "0", "DAILY_GLOBAL_LIMIT": "x", "CARE_SETTING": "hospital", "REQUIRE_LOGIN": "yes"} {
		if _, err := LoadAccounts(env(map[string]string{k: v})); err == nil {
			t.Errorf("F-031 AC4 %s=%s 는 오류여야 함", k, v)
		}
	}
}
