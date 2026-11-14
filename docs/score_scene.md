# 결과 출력 씬

기준은 feature/npc-interaction의 b2177e8(prototype)입니다.
기존 실행 경로: 로그인 → 메인 메뉴 → scenes/field/myroom.tscn → Q로 휴대폰 → 일정 선택 → scenes/field/test1.tscn.

편의점의 일정 종료 버튼은 기존 test_1.gd에서 Record.session_records를
http://127.0.0.1:8000/api/pronunciation/assess 로 전송합니다.
audio, reference_text, locale 요청 필드와 서버 주소는 기존 그대로입니다.
_on_one_request_done(res, file_name)의 네 점수를 결과 카드에 전달합니다.
모든 응답이 끝나면 결과창이 나타나고, 닫기 또는 Esc 후 기존 myroom.tscn으로 돌아갑니다.
실패 또는 잘못된 응답은 점수 대신 — 로 표시합니다.
녹음이 없으면 기존처럼 바로 귀가합니다.

- scripts/scores/score_result.gd: 점수 검증 및 표시 형식
- scripts/scores/score_presenter.gd: 콜백 결과 수집 및 화면 연결
- scenes/scores/print_score_scene.tscn: 전체 결과 화면
- scenes/scores/score_card.tscn: 파일별 결과 카드
- scenes/scores/score_metric.tscn: 점수 한 항목

tests/score_integration.gd는 실제 test_1.gd 콜백과 결과창 닫기 후 귀가를
서버·마이크 없이 검사합니다. 실제 서버와의 통신은 별도 확인이 필요합니다.
실행: godot --headless --path . --rendering-method gl_compatibility --script res://tests/score_integration.gd
