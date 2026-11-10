// Package contract는 채팅 서버의 HTTP 계약 테스트다 (SPEC.md F-009·F-013, ARCHITECTURE.md ADR-012).
//
// 화면이 보는 API(SPEC.md §9)가 바뀌지 않았는지 실제 HTTP 요청으로 확인한다.
//
//	go test ./contract                                   # chatd를 빌드해 모의 모드로 직접 띄운다
//	go test ./contract -base-url=http://127.0.0.1:3000   # 이미 떠 있는 서버에 실행
//
// 서버는 모의 모드(ANTHROPIC_API_KEY 미설정)여야 한다. 모의 모드가 아니면
// 채팅 요청을 보내기 전에 실패한다. 직접 띄울 때는 키를 넘기지 않는다.
//
// 표준 라이브러리만 사용한다.
package contract
