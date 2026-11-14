extends RefCounted
## 서버 응답 검증과 표시 형식. UI나 네트워크 상태를 변경하지 않습니다.

const FIELDS := {
	"accuracy_score": "정확도",
	"fluency_score": "유창성",
	"completeness_score": "완전성",
	"pron_score": "종합",
}


static func from_response(response_text: String) -> Variant:
	var json := JSON.new()
	if json.parse(response_text) != OK: return null
	var parsed: Variant = json.data
	return parsed if is_valid(parsed) else null


static func is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in FIELDS:
		var score: Variant = value.get(key)
		if score is String:
			if not score.is_valid_float(): return false
		elif not (score is int or score is float):
			return false
		if not is_finite(float(score)): return false
	return true


static func format_score(value: Variant) -> String:
	return ("%.2f" % float(value)).rstrip("0").rstrip(".")
