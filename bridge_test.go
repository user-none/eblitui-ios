package ios

import (
	"encoding/json"
	"testing"

	"github.com/user-none/eblitui/coreif"
)

func TestCategoryString(t *testing.T) {
	tests := []struct {
		cat  coreif.CoreOptionCategory
		want string
	}{
		{coreif.CoreOptionCategoryAudio, "Audio"},
		{coreif.CoreOptionCategoryVideo, "Video"},
		{coreif.CoreOptionCategoryInput, "Input"},
		{coreif.CoreOptionCategoryCore, "Core"},
		{coreif.CoreOptionCategory(99), "Core"},
	}

	for _, tt := range tests {
		got := categoryString(tt.cat)
		if got != tt.want {
			t.Errorf("categoryString(%d) = %q, want %q", tt.cat, got, tt.want)
		}
	}
}

type mockFactory struct{}

func (f *mockFactory) SystemInfo() coreif.SystemInfo {
	return coreif.SystemInfo{
		Name:        "test",
		ConsoleName: "Test Console",
		Extensions:  []string{".bin"},
		CoreOptions: []coreif.CoreOption{
			{
				Key:      "opt_audio",
				Label:    "Audio Option",
				Category: coreif.CoreOptionCategoryAudio,
			},
			{
				Key:      "opt_input",
				Label:    "Input Option",
				Category: coreif.CoreOptionCategoryInput,
			},
			{
				Key:      "opt_video",
				Label:    "Video Option",
				Category: coreif.CoreOptionCategoryVideo,
			},
			{
				Key:      "opt_core",
				Label:    "Core Option",
				Category: coreif.CoreOptionCategoryCore,
			},
		},
	}
}

func (f *mockFactory) CreateEmulator(rom []byte, region coreif.Region) (coreif.Emulator, error) {
	return nil, nil
}

func (f *mockFactory) DetectRegion(rom []byte) (coreif.Region, bool) {
	return coreif.RegionNTSC, false
}

func TestSystemInfoJSONCategoryStrings(t *testing.T) {
	old := factory
	defer func() { factory = old }()

	factory = &mockFactory{}

	result := SystemInfoJSON()

	var parsed struct {
		CoreOptions []struct {
			Key      string `json:"Key"`
			Category string `json:"Category"`
		} `json:"CoreOptions"`
	}
	if err := json.Unmarshal([]byte(result), &parsed); err != nil {
		t.Fatalf("failed to parse SystemInfoJSON: %v", err)
	}

	if len(parsed.CoreOptions) != 4 {
		t.Fatalf("expected 4 core options, got %d", len(parsed.CoreOptions))
	}

	expected := map[string]string{
		"opt_audio": "Audio",
		"opt_input": "Input",
		"opt_video": "Video",
		"opt_core":  "Core",
	}

	for _, opt := range parsed.CoreOptions {
		want, ok := expected[opt.Key]
		if !ok {
			t.Errorf("unexpected option key: %s", opt.Key)
			continue
		}
		if opt.Category != want {
			t.Errorf("option %s: category = %q, want %q", opt.Key, opt.Category, want)
		}
	}
}
