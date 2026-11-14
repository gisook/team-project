# team-project · top_down_map

## 결과 출력 화면씬 제작 및 연결 · print_score_scene

`feature/npc-interaction` 기준의 결과 화면입니다. 녹음 업로드 응답의
`accuracy_score`(정확도), `fluency_score`(유창성),
`completeness_score`(완전성), `pron_score`(종합)을 파일별로 표시합니다.
서버가 반환한 종합 점수를 그대로 사용하며 점수는 소수 둘째 자리까지 표시합니다.
응답은 이 네 필드를 포함하는 JSON 객체여야 합니다. 중첩된 응답을 사용하는 서버라면
`score_result.gd`의 `from_response()`에서 응답 구조를 변환하세요.

- `scripts/scores/score_result.gd`: JSON 검증, 필드 이름, 숫자 표시 형식.
- `scripts/scores/score_presenter.gd`: 업로드 시그널 구독, `_on_one_request_done(res, file_name)` 수집과 콘솔 출력, 화면 연결.
- `scenes/scores/print_score_scene.tscn` + `scripts/scores/score_screen.gd`: 스크롤 가능한 전체 결과 화면, 요약, 닫기와 Esc 처리.
- `scenes/scores/score_card.tscn` + `scripts/scores/score_card.gd`: 파일별 결과 카드와 평가 실패 안내.
- `scenes/scores/score_metric.tscn` + `scripts/scores/score_metric.gd`: 재사용 가능한 점수 한 항목.

탑다운 화면은 업로드 종료 후 대화·장소 전환이 끝나면 결과를 자동 표시합니다.
상단 **평가 결과 보기**로 가장 최근 전송 결과를 다시 볼 수 있습니다.
결과를 확인하는 동안 이동·상호작용을 막고 닫으면 같은 위치에서 이어갑니다.
기존 대화 화면도 같은 결과 화면을 사용하며, 일정을 마쳤을 때는 결과 창을 닫은 뒤 방으로 돌아갑니다.
빈 결과, 실제 0점, 부분 성공·실패를 구별합니다. 통신 실패나 잘못된 점수 응답은
평가 실패로 표시하고 해당 WAV를 미전송 목록에 보관해 기존 전송 버튼으로 재시도합니다.
실패 이후 아직 요청하지 않은 파일은 결과 카드에서 제외합니다.
결과는 현재 화면의 메모리에 유지하며 새 전송을 시작하면 초기화합니다.

다른 평가 요청 코드에서도 `ScorePresenter`를 노드로 추가한 뒤
`_on_one_request_done(res, file_name)`으로 전달하고 `show_results()`로 표시할 수 있습니다.
`print_score_scene.tscn`은 에디터에서 독립 실행하면 빈 결과 화면을 확인할 수 있습니다.

검증 명령 (마이크·네트워크 없이 응답 데이터로 검사):

```text
godot --headless --path . --rendering-method gl_compatibility --script res://tests/score_integration.gd
godot --headless --path . --rendering-method gl_compatibility --script res://tests/top_down_integration.gd
godot --path . --rendering-method gl_compatibility --script res://tests/score_integration.gd -- --preview
```

마지막 명령은 `artifacts/` 폴더가 있을 때 결과 화면 PNG를 저장합니다.
점수 검증 테스트의 잘못된 응답 사례에서 나오는 평가 실패 로그는 의도된 출력입니다.
실제 서버 응답 형식과 실제 마이크 녹음은 별도 실행 환경에서 확인해야 합니다.

기능추가
1. 자기 방에서 상하좌우 이동 가능
2. 일정을 수행할 장소에서 이동 가능

Godot 4.7 기반 탑다운 대화·녹음 프로토타입입니다. `feature/npc-interaction`에서 편집한 방(`scenes/field/myroom.tscn`)과 편의점(`scenes/field/test1.tscn`)을 실제 하루 진행에 연결합니다. `project.godot`을 열고 실행하면 기존 로그인 화면에서 시작합니다. 게임 시작 후 침대 옆에 나타납니다. 하루 진행 화면만 확인하려면 `scenes/room.tscn`을 실행하세요.

## 조작과 하루 진행

- **W/A/S/D**: 상하좌우 이동. 업로드된 맵의 바닥과 가구 타일을 기준으로 이동 가능 여부를 계산하고 벽·가구·손님과 충돌합니다. 맵의 현재 바닥 크기는 벽을 제외한 **15×16칸**입니다.
- **E**: 근처 물체·손님과 상호작용. 안내 문구가 화면 아래에 나타납니다.
- **Esc**: 휴대폰 닫기, 또는 답변 선택 전 대화 닫기.

오전에는 오른쪽 책상 아래쪽의 휴대폰 근처에서 E → 편의점 알바 선택 → 편의점으로 이동하고 근무복으로 변경됩니다. 손님 세 명이 편의점 아래쪽에서 계산대·진열대·음료 냉장고로 이동합니다. 계산대 손님은 왼쪽 위 계산대 안쪽 계산원 자리에서, 나머지 손님은 옆 칸에서 E로 응대합니다. 응대할 수 있는 가장 가까운 손님이 밝게 표시됩니다.

방과 편의점의 원본 타일 배치를 사용하며, 방에는 휴대폰과 시간대 창문, 편의점 오른쪽 아래에는 음료 냉장고를 보충합니다. 계산원 자리에서 진열대로 걸어 나갈 수 있도록 게임 실행 시 계산대 타일 한 칸을 출입구로 엽니다. 원본 맵 장면을 편집하는 대신 연결 화면에서 이 보충 요소를 적용하므로 원본 맵의 타일 데이터는 유지됩니다.

NPC 머리 위 말풍선에 질문이 나타나며 화면 중간부터 아래에 답변 선택지가 나옵니다. 답변 선택 → 녹음 시작 → 녹음 종료 및 저장을 하면 손님의 답변 후 응대가 완료됩니다. 세 명 모두 응대하면 오후의 방으로 돌아옵니다. 오후에도 같은 일정을 수행하면 밤이 됩니다. 밤에는 침대 옆에서 E → 눕기 → 암전 → 다음 날 아침 침대 옆에서 시작합니다.

학생·아줌마는 매 근무 등장하고, 세 번째 손님은 청년과 노인이 시간대·날짜에 따라 번갈아 등장합니다. 한 근무의 손님 수는 항상 세 명입니다. 책상에는 기능이 없고, 휴대폰은 오전·오후, 침대는 밤에만 사용할 수 있습니다. 벽의 창문은 해의 높이와 달로 시간대를 표시합니다.

## 저장과 녹음

계정별 날짜·시간대·진행 중인 근무와 완료한 손님을 로컬 저장합니다. 재시작하면 완료한 응대는 유지하며 나머지 손님은 입구부터 다시 이동합니다. 기존 버전에서 진행 중이던 대화는 기존 대화 화면에서 이어집니다.

WAV 파일은 `user://recordings/<shift_id>/`에 저장하며, 선택 문장·손님·날짜·시간대·파일 경로는 계정별 `user://map_recordings_<account_hash>.json`에 보관합니다. 근무 종료 후 기존 서버의 `/upload`로 백그라운드 전송하므로 이동을 계속할 수 있습니다. 실패한 파일은 남겨 두며 화면 위의 **미전송 녹음 전송**으로 재시도합니다. 녹음에는 운영체제의 마이크 허용이 필요합니다. 로그인·업로드 서버 주소는 기존 프로젝트 설정을 사용합니다.

## 구현과 검증

- `scripts/top_down_world.gd`: 이동, 충돌, 손님 경로 탐색, 상호작용, 녹음과 하루 진행.
- `scripts/authored_map.gd`: 편집한 TileMap 장면·플레이어·NPC 인스턴스를 렌더링하고 타일 기반 충돌, 시간대와 응대 하이라이트를 연결합니다. 단독 맵 실행에서는 기존 이동 스크립트를 사용하고, 하루 진행 화면에서는 공통 컨트롤러가 이동과 상호작용을 담당합니다.
- `scripts/top_down_map.gd`: 이전 도형 기반 맵 렌더러 보관본입니다.
- `scripts/store_dialogues.gd`: 손님 세 명의 목적지와 한국어 대화 데이터.
- `scripts/day_state.gd`: 기존 계정·일차 저장에 근무 진행 상태 추가.

Godot 명령줄에서 다음 검사들을 실행할 수 있습니다. 테스트는 별도 테스트 계정으로 실행하며 마이크와 네트워크를 사용하지 않습니다. 실제 로그인 서버 인증과 실제 마이크 음질은 별도 환경에서 확인해야 합니다.

```text
godot --headless --path . --rendering-method gl_compatibility --script res://tests/top_down_integration.gd
godot --path . --rendering-method gl_compatibility --script res://tests/capture_preview.gd
```

두 번째 명령은 `artifacts/` 폴더에 방·편의점·휴대폰·대화 화면 PNG를 저장합니다. 폴더가 없다면 먼저 생성하세요.

## 이미지 출처

`assets/modern/`은 사용자가 제공한 **Modern Interiors Free v2.2**의 원본 타일과 캐릭터입니다. 함께 제공된 `assets/modern/LICENSE.txt`에 따라 **비상업적 프로젝트에서만 사용·수정할 수 있습니다**. 상업적 배포에는 별도 적합한 라이선스가 필요합니다.

`assets/generated/furniture.png`는 제공된 그림체를 참고해 이미지 생성 도구로 보충한 침대·음료 냉장고 이미지입니다. 생성 지시문은 `assets/generated/PROMPT.md`에 보관합니다. 책상·휴대폰·계산대·유니폼 및 노인의 흰머리와 지팡이는 원본 그림체에 맞춘 게임 내 도형으로 표현합니다.
