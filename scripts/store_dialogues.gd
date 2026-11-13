extends RefCounted

# A shift always has exactly three destinations. The cast rotates to include four appearances.
static func customers(day: int, period: String) -> Array[Dictionary]:
	var elder := (day + (1 if period == "afternoon" else 0)) % 2 == 0
	return [
		{"id": "counter", "name": "학생", "appearance": "Alex",
		"question": "안녕하세요! 이 삼각김밥이랑 우유 계산해 주세요. 봉투도 하나 살 수 있을까요?",
		"choices": ["네, 봉투 함께 드릴게요. 결제는 어떻게 하시겠어요?", "안녕하세요! 봉투는 유료인데 괜찮으세요?"],
		"reply": "네, 괜찮아요. 카드로 할게요. 감사합니다!"},
		{"id": "shelf", "name": "아줌마", "appearance": "Amelia",
		"question": "저기요, 덜 매운 컵라면을 찾고 있는데 어떤 게 좋을까요?",
		"choices": ["이쪽의 순한 맛 제품은 어떠세요? 제가 안내해 드릴게요.", "매운 걸 잘 못 드시면 이 우동도 괜찮아요."],
		"reply": "아, 여기 있었네요. 알려줘서 고마워요. 이걸로 살게요."},
		{"id": "fridge", "name": "노인" if elder else "청년", "appearance": "Bob" if elder else "Adam",
		"question": "실례해요. 차갑지 않은 생수도 있나요?" if elder else "운동하고 왔는데요, 이 음료 지금 행사 중인가요?",
		"choices": ["네, 실온 생수는 옆 진열대에 있어요. 가져다드릴까요?", "네, 차갑지 않은 생수로 찾아드릴게요."] if elder else ["네, 같은 상품 두 개를 고르시면 하나 더 드려요.", "네! 행사 표시가 있는 맛끼리 함께 고르셔도 돼요."],
		"reply": "친절하게 알려줘서 고마워요. 덕분에 잘 골랐네요."}
	]
