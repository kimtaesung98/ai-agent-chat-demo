package config

import (
	"fmt"
	"strconv"
	"strings"
)

// Accounts는 계정·저장소·사용량 상한 설정이다 (SPEC.md F-026·F-030, ARCHITECTURE.md §6.3).
// BootstrapAdminCode는 비밀값이라 로그·응답에 쓰지 않는다.
type Accounts struct {
	DataDir            string // 비면 메모리 DB
	GoogleClientID     string // 비면 Google 로그인 꺼짐
	GuestMode          bool
	RequireLogin       bool   // 실제 모드에서 세션 없는 AI 경로를 닫는다. 앱 로그인 화면(단계 7-⑤) 전까지 기본 꺼짐
	BootstrapAdminCode string // 있으면 최고 관리자가 없을 때 이 코드로 첫 최고 관리자를 만든다
	BootstrapAdminName string
	ClientIPHeader     string // 프록시가 넣는 진짜 IP 헤더 (예 CF-Connecting-IP). 비면 연결 주소
	CareSetting        string // daycare · nursing_home · home_alone (ADR-035)

	GuestTurns, GuestPerIPHourly, GuestDailyTotal      int
	UserDailyTurns, AdminDailyTurns, VoiceDailyMinutes int
	DailyGlobalLimit                                   int
}

// CareSettings는 알려진 배포 유형이다.
var CareSettings = []string{"daycare", "nursing_home", "home_alone"}

// LoadAccounts는 계정 설정을 읽는다. 값이 잘못되면 오류.
func LoadAccounts(getenv func(string) string) (Accounts, error) {
	get := func(k string) string { return strings.TrimSpace(getenv(k)) }
	a := Accounts{
		DataDir:            get("DATA_DIR"),
		GoogleClientID:     get("GOOGLE_CLIENT_ID"),
		BootstrapAdminCode: get("BOOTSTRAP_ADMIN_CODE"),
		BootstrapAdminName: get("BOOTSTRAP_ADMIN_NAME"),
		ClientIPHeader:     get("CLIENT_IP_HEADER"),
		CareSetting:        get("CARE_SETTING"),
	}
	switch g := strings.ToLower(get("GUEST_MODE")); g {
	case "", "off", "false", "0":
	case "on", "true", "1":
		a.GuestMode = true
	default:
		return Accounts{}, fmt.Errorf("GUEST_MODE는 on 또는 off여야 해요 (받은 값: %q)", g)
	}
	switch g := strings.ToLower(get("REQUIRE_LOGIN")); g {
	case "", "off", "false", "0":
	case "on", "true", "1":
		a.RequireLogin = true
	default:
		return Accounts{}, fmt.Errorf("REQUIRE_LOGIN은 on 또는 off여야 해요 (받은 값: %q)", g)
	}
	if a.BootstrapAdminName == "" {
		a.BootstrapAdminName = "최고 관리자"
	}
	if a.CareSetting == "" {
		a.CareSetting = "daycare"
	}
	known := false
	for _, c := range CareSettings {
		known = known || c == a.CareSetting
	}
	if !known {
		return Accounts{}, fmt.Errorf("CARE_SETTING은 %s 중 하나여야 해요 (받은 값: %q)", strings.Join(CareSettings, ", "), a.CareSetting)
	}
	ints := []struct {
		key string
		dst *int
		def int
	}{
		{"GUEST_TURNS", &a.GuestTurns, 10},
		{"GUEST_PER_IP_HOURLY", &a.GuestPerIPHourly, 3},
		{"GUEST_DAILY_TOTAL", &a.GuestDailyTotal, 300},
		{"USER_DAILY_TURNS", &a.UserDailyTurns, 300},
		{"ADMIN_DAILY_TURNS", &a.AdminDailyTurns, 500},
		{"VOICE_DAILY_MINUTES", &a.VoiceDailyMinutes, 60},
		{"DAILY_GLOBAL_LIMIT", &a.DailyGlobalLimit, 5000},
	}
	for _, it := range ints {
		*it.dst = it.def
		if v := get(it.key); v != "" {
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 1_000_000 {
				return Accounts{}, fmt.Errorf("%s는 1~1000000 사이 숫자여야 해요 (받은 값: %q)", it.key, v)
			}
			*it.dst = n
		}
	}
	return a, nil
}
