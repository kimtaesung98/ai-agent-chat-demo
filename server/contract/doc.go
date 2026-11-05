// Package contract는 채팅 서버의 HTTP 계약 테스트다 (SPEC.md F-009, ARCHITECTURE.md ADR-012).
//
// 같은 테스트를 Node 서버와 Go 서버에 똑같이 실행해, 서버를 바꿔도 화면이 보는 API가
// 그대로인지 확인한다. 테스트는 실행 중인 서버에 실제 HTTP 요청을 보낸다.
//
//	go test ./contract -base-url=http://127.0.0.1:3000
//
// 서버는 모의 모드(ANTHROPIC_API_KEY 미설정)로 떠 있어야 한다. 모의 모드가 아니면
// 채팅 요청을 보내기 전에 실패한다. -base-url이 없으면 아무것도 실행하지 않고 끝난다.
//
// 표준 라이브러리만 사용한다.
package contract
