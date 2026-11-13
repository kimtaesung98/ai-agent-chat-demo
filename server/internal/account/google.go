package account

import (
	"context"
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"math/big"
	"net/http"
	"strings"
	"sync"
	"time"
)

// GoogleIdentity는 확인한 Google ID 토큰의 내용이다.
type GoogleIdentity struct {
	Subject       string
	Email         string
	EmailVerified bool
}

// GoogleVerifier는 Google ID 토큰을 확인한다.
type GoogleVerifier interface {
	Verify(ctx context.Context, idToken string) (GoogleIdentity, error)
}

// GoogleCertsURL은 Google 공개 키(JWKS) 주소다.
const GoogleCertsURL = "https://www.googleapis.com/oauth2/v3/certs"

// JWKSVerifier는 표준 라이브러리로 RS256 서명·iss·aud·exp를 확인한다 (ADR-017·029). 공개 키는 1시간 캐시.
type JWKSVerifier struct {
	ClientID string
	CertsURL string // 비면 GoogleCertsURL (테스트는 가짜 서버)
	Client   *http.Client
	Now      func() time.Time

	mu      sync.Mutex
	keys    map[string]*rsa.PublicKey
	fetched time.Time
}

var errToken = errors.New("google: invalid token")

func (v *JWKSVerifier) now() time.Time {
	if v.Now != nil {
		return v.Now()
	}
	return time.Now()
}

// Verify는 토큰을 확인한다. 어떤 이유로 실패해도 같은 오류를 돌려준다 (토큰 내용은 로그에 남기지 않음).
func (v *JWKSVerifier) Verify(ctx context.Context, idToken string) (GoogleIdentity, error) {
	parts := strings.Split(idToken, ".")
	if len(parts) != 3 || len(idToken) > 8192 {
		return GoogleIdentity{}, errToken
	}
	var header struct {
		Alg string `json:"alg"`
		Kid string `json:"kid"`
	}
	if !decodePart(parts[0], &header) || header.Alg != "RS256" || header.Kid == "" {
		return GoogleIdentity{}, errToken
	}
	key, err := v.key(ctx, header.Kid)
	if err != nil {
		return GoogleIdentity{}, errToken
	}
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		return GoogleIdentity{}, errToken
	}
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig) != nil {
		return GoogleIdentity{}, errToken
	}
	var claims struct {
		Iss           string          `json:"iss"`
		Aud           string          `json:"aud"`
		Sub           string          `json:"sub"`
		Exp           int64           `json:"exp"`
		Email         string          `json:"email"`
		EmailVerified json.RawMessage `json:"email_verified"` // true 또는 "true"
	}
	if !decodePart(parts[1], &claims) {
		return GoogleIdentity{}, errToken
	}
	if claims.Iss != "accounts.google.com" && claims.Iss != "https://accounts.google.com" {
		return GoogleIdentity{}, errToken
	}
	if v.ClientID == "" || claims.Aud != v.ClientID || claims.Sub == "" || v.now().Unix() >= claims.Exp {
		return GoogleIdentity{}, errToken
	}
	ev := strings.Trim(string(claims.EmailVerified), `"`) == "true"
	return GoogleIdentity{Subject: claims.Sub, Email: claims.Email, EmailVerified: ev}, nil
}

func decodePart(s string, v any) bool {
	b, err := base64.RawURLEncoding.DecodeString(s)
	return err == nil && json.Unmarshal(b, v) == nil
}

func (v *JWKSVerifier) key(ctx context.Context, kid string) (*rsa.PublicKey, error) {
	v.mu.Lock()
	defer v.mu.Unlock()
	if k, ok := v.keys[kid]; ok && v.now().Sub(v.fetched) < time.Hour {
		return k, nil
	}
	if err := v.fetch(ctx); err != nil {
		return nil, err
	}
	if k, ok := v.keys[kid]; ok {
		return k, nil
	}
	return nil, errToken
}

func (v *JWKSVerifier) fetch(ctx context.Context) error {
	url := v.CertsURL
	if url == "" {
		url = GoogleCertsURL
	}
	client := v.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return errToken
	}
	var set struct {
		Keys []struct {
			Kid string `json:"kid"`
			Kty string `json:"kty"`
			N   string `json:"n"`
			E   string `json:"e"`
		} `json:"keys"`
	}
	if err := json.NewDecoder(io.LimitReader(res.Body, 1<<20)).Decode(&set); err != nil {
		return err
	}
	keys := map[string]*rsa.PublicKey{}
	for _, k := range set.Keys {
		n, err1 := base64.RawURLEncoding.DecodeString(k.N)
		e, err2 := base64.RawURLEncoding.DecodeString(k.E)
		if k.Kty != "RSA" || err1 != nil || err2 != nil || len(e) > 4 {
			continue
		}
		keys[k.Kid] = &rsa.PublicKey{N: new(big.Int).SetBytes(n), E: int(new(big.Int).SetBytes(e).Int64())}
	}
	v.keys, v.fetched = keys, v.now()
	return nil
}
