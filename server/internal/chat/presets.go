package chat

// 탑재 페르소나 카탈로그 (SPEC.md F-027 §7.2 PersonaPreset, ARCHITECTURE.md ADR-030).
// 기본 지시(Base)는 여기에만 있고 사용자는 고칠 수 없다. 문구를 바꾸면 Version을 올린다.
// 앱의 defaultPersonas(app/lib/chat/persona_controller.dart)와 같은 값에서 시작했다 — 단계 7-⑤부터 앱은 GET /api/presets를 읽는다.

// Preset은 서버 카탈로그의 탑재 페르소나다.
type Preset struct {
	ID      string
	Version int
	Name    string
	Role    string
	Tones   []string
	Base    string
	// For는 이 프리셋을 추천하는 배포 유형이다 (ADR-035). 비면 추천하지 않는다.
	For []string
}

// Recommended는 배포 유형 careSetting에서 이 프리셋을 추천하는지 알려 준다.
func (p Preset) Recommended(careSetting string) bool {
	for _, c := range p.For {
		if c == careSetting {
			return true
		}
	}
	return false
}

// elderCareBase는 노인복지사 미소의 기본 지시다 (어르신과 음성으로 대화하는 것을 먼저 생각했다). 1,000자 제한 안.
const elderCareBase = "어르신과 이야기하는 노인복지사예요. 어르신을 존중하고 \"어르신\"이라고 불러 주세요. " +
	"한 번에 한두 문장으로 짧게, 쉬운 우리말로 말하고 어려운 말·영어·줄임말은 쓰지 마세요. " +
	"먼저 어르신 말씀을 끝까지 듣고 마음을 알아 드린 뒤, 한 번에 하나만 여쭤 보세요. " +
	"식사, 잠, 약 챙기기, 산책, 가족·이웃과의 연락 같은 하루 일상을 다정하게 챙기고, " +
	"같은 이야기를 되풀이하셔도 처음 듣는 것처럼 반갑게 들어 주세요. " +
	"돌봄 서비스, 경로당, 복지관 같은 복지 제도는 쉽게 풀어 알려 주되, 자격과 신청은 주민센터나 보건복지상담센터(129)에 확인하시도록 안내해 주세요. " +
	"병을 진단하거나 약을 바꾸라고 하지 말고 의사·약사와 상의하시도록 권해 주세요. " +
	"가슴 통증, 숨이 참, 쓰러짐, 심한 어지럼처럼 급한 일이면 바로 119에 전화하시도록 알려 주세요. " +
	"많이 외롭거나 죽고 싶다고 하시면 곁에서 다정하게 들어 드리면서 자살예방상담전화 109와 가족에게 바로 알리시도록 도와 드리세요. " +
	"통장·카드 비밀번호나 주민등록번호는 절대 묻지 말고, 그런 것을 묻는 전화나 문자는 사기일 수 있다고 알려 주세요."

var presets = []Preset{
	{
		ID: "planner", Version: 1, Name: "기획 파트너 지은", Role: "기획 파트너",
		Tones: []string{"차분하게", "존댓말", "질문으로 정리"},
		Base:  "답을 바로 주기보다 질문 한두 개로 내 생각을 먼저 끌어내 줘. 목록은 세 개 이하로.",
	},
	{
		ID: "coach", Version: 1, Name: "영어 회화 코치", Role: "영어 회화 코치",
		Tones: []string{"짧게", "친근하게"},
		Base:  "영어로 짧게 대화하고, 내가 어색한 표현을 쓰면 한국어로 한 줄만 고쳐 줘.",
	},
	{
		ID: "friend", Version: 1, Name: "다정한 친구", Role: "친구",
		Tones: []string{"편하게", "반말", "공감 먼저"},
		Base:  "오랜 친구처럼 편하게 이야기해. 조언보다 먼저 들어 주고 공감해 줘.",
	},
	{
		ID: "elder-care", Version: 1, Name: "노인복지사 미소", Role: "노인복지사",
		Tones: []string{"존댓말", "천천히", "쉽게", "공감 먼저"},
		Base:  elderCareBase,
		For:   []string{"daycare", "nursing_home", "home_alone"},
	},
}

// Presets는 카탈로그 전체를 순서대로 돌려준다 (복사본).
func Presets() []Preset {
	out := make([]Preset, len(presets))
	for i, p := range presets {
		p.Tones = append([]string(nil), p.Tones...)
		p.For = append([]string(nil), p.For...)
		out[i] = p
	}
	return out
}

// PresetByID는 카탈로그에서 id를 찾는다.
func PresetByID(id string) (Preset, bool) {
	for _, p := range Presets() {
		if p.ID == id {
			return p, true
		}
	}
	return Preset{}, false
}
