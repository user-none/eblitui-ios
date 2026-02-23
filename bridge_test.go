package ios

import (
	"encoding/json"
	"testing"

	emucore "github.com/user-none/eblitui/api"
)

func TestCategoryString(t *testing.T) {
	tests := []struct {
		cat  emucore.CoreOptionCategory
		want string
	}{
		{emucore.CoreOptionCategoryAudio, "Audio"},
		{emucore.CoreOptionCategoryVideo, "Video"},
		{emucore.CoreOptionCategoryInput, "Input"},
		{emucore.CoreOptionCategoryCore, "Core"},
		{emucore.CoreOptionCategory(99), "Core"},
	}

	for _, tt := range tests {
		got := categoryString(tt.cat)
		if got != tt.want {
			t.Errorf("categoryString(%d) = %q, want %q", tt.cat, got, tt.want)
		}
	}
}

type mockFactory struct{}

func (f *mockFactory) SystemInfo() emucore.SystemInfo {
	return emucore.SystemInfo{
		Name:        "test",
		ConsoleName: "Test Console",
		Extensions:  []string{".bin"},
		CoreOptions: []emucore.CoreOption{
			{
				Key:      "opt_audio",
				Label:    "Audio Option",
				Category: emucore.CoreOptionCategoryAudio,
			},
			{
				Key:      "opt_input",
				Label:    "Input Option",
				Category: emucore.CoreOptionCategoryInput,
			},
			{
				Key:      "opt_video",
				Label:    "Video Option",
				Category: emucore.CoreOptionCategoryVideo,
			},
			{
				Key:      "opt_core",
				Label:    "Core Option",
				Category: emucore.CoreOptionCategoryCore,
			},
		},
	}
}

func (f *mockFactory) CreateEmulator(rom []byte, region emucore.Region) (emucore.Emulator, error) {
	return nil, nil
}

func (f *mockFactory) DetectRegion(rom []byte) (emucore.Region, bool) {
	return emucore.RegionNTSC, false
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
