package ios

import (
	"encoding/json"
	"fmt"
	emucore "github.com/user-none/eblitui/api"
	"github.com/user-none/eblitui/romloader"
	"hash/crc32"
	"os"
	"path/filepath"
	"strings"
)

var (
	factory      emucore.CoreFactory
	emu          emucore.Emulator
	saveStater   emucore.SaveStater
	batterySaver emucore.BatterySaver

	// cached data
	frameData []byte
	audioData []byte
	stateData []byte
	sramData  []byte
)

// RegisterFactory sets the CoreFactory. Called by core's init().
func RegisterFactory(f emucore.CoreFactory) {
	factory = f
}

// Init creates an emulator from a ROM file path.
// regionCode: 0=NTSC, 1=PAL
// Returns true on success.
func Init(path string, regionCode int) bool {
	if factory == nil {
		return false
	}

	info := factory.SystemInfo()
	rom, _, err := romloader.Load(path, info.Extensions)
	if err != nil {
		return false
	}

	region := emucore.Region(regionCode)
	e, err := factory.CreateEmulator(rom, region)
	if err != nil {
		return false
	}

	emu = e

	// Detect optional interfaces
	saveStater, _ = e.(emucore.SaveStater)
	batterySaver, _ = e.(emucore.BatterySaver)

	return true
}

// Close releases the emulator.
func Close() {
	if emu != nil {
		emu.Close()
	}
	emu = nil
	saveStater = nil
	batterySaver = nil
	frameData = nil
	audioData = nil
	stateData = nil
	sramData = nil
}

// RunFrame executes one frame of emulation.
func RunFrame() {
	if emu == nil {
		return
	}

	emu.RunFrame()

	// Cache frame buffer - only the active display area
	fullBuffer := emu.GetFramebuffer()
	activeHeight := emu.GetActiveHeight()
	stride := emu.GetFramebufferStride()
	activeBytes := stride * activeHeight
	if activeBytes <= len(fullBuffer) {
		frameData = fullBuffer[:activeBytes]
	} else {
		frameData = fullBuffer
	}

	// Convert audio samples to little-endian bytes
	samples := emu.GetAudioSamples()
	if len(samples) > 0 {
		needed := len(samples) * 2
		if cap(audioData) < needed {
			audioData = make([]byte, needed)
		} else {
			audioData = audioData[:needed]
		}
		for i, s := range samples {
			audioData[i*2] = byte(s)
			audioData[i*2+1] = byte(s >> 8)
		}
	} else {
		audioData = nil
	}
}

// GetFrameData returns the frame buffer for the active display area.
func GetFrameData() []byte {
	return frameData
}

// GetAudioData returns audio as int16 stereo PCM little-endian bytes.
func GetAudioData() []byte {
	return audioData
}

// SetInput sets controller state as a button bitmask for the given player.
func SetInput(player int, buttons int) {
	if emu != nil {
		emu.SetInput(player, uint32(buttons))
	}
}

// FrameWidth returns the display width in pixels.
func FrameWidth() int {
	if emu == nil {
		if factory != nil {
			return factory.SystemInfo().ScreenWidth
		}
		return 0
	}
	return emu.GetFramebufferStride() / 4
}

// FrameStride returns the framebuffer stride in bytes per row.
func FrameStride() int {
	if emu == nil {
		if factory != nil {
			return factory.SystemInfo().ScreenWidth * 4
		}
		return 0
	}
	return emu.GetFramebufferStride()
}

// FrameHeight returns the active display height.
func FrameHeight() int {
	if emu == nil {
		if factory != nil {
			return factory.SystemInfo().MaxScreenHeight
		}
		return 0
	}
	return emu.GetActiveHeight()
}

// categoryString converts a CoreOptionCategory to its display name for iOS.
func categoryString(c emucore.CoreOptionCategory) string {
	switch c {
	case emucore.CoreOptionCategoryAudio:
		return "Audio"
	case emucore.CoreOptionCategoryVideo:
		return "Video"
	case emucore.CoreOptionCategoryInput:
		return "Input"
	default:
		return "Core"
	}
}

// jsonCoreOption mirrors emucore.CoreOption with Category as a string
// for iOS JSON serialization.
type jsonCoreOption struct {
	Key         string                 `json:"Key"`
	Label       string                 `json:"Label"`
	Description string                 `json:"Description"`
	Type        emucore.CoreOptionType `json:"Type"`
	Default     string                 `json:"Default"`
	Values      []string               `json:"Values,omitempty"`
	Min         int                    `json:"Min"`
	Max         int                    `json:"Max"`
	Step        int                    `json:"Step"`
	Category    string                 `json:"Category"`
	PerGame     bool                   `json:"PerGame"`
}

// SystemInfoJSON returns the system info as a JSON string.
// CoreOptionCategory values are serialized as display strings.
func SystemInfoJSON() string {
	if factory == nil {
		return "{}"
	}

	info := factory.SystemInfo()

	options := make([]jsonCoreOption, len(info.CoreOptions))
	for i, opt := range info.CoreOptions {
		options[i] = jsonCoreOption{
			Key:         opt.Key,
			Label:       opt.Label,
			Description: opt.Description,
			Type:        opt.Type,
			Default:     opt.Default,
			Values:      opt.Values,
			Min:         opt.Min,
			Max:         opt.Max,
			Step:        opt.Step,
			Category:    categoryString(opt.Category),
			PerGame:     opt.PerGame,
		}
	}

	// Embed SystemInfo and override CoreOptions with string categories.
	data, err := json.Marshal(struct {
		emucore.SystemInfo
		CoreOptions []jsonCoreOption `json:"CoreOptions"`
	}{
		SystemInfo:  info,
		CoreOptions: options,
	})
	if err != nil {
		return "{}"
	}
	return string(data)
}

// Region returns the current region (0=NTSC, 1=PAL).
func Region() int {
	if emu == nil {
		return 0
	}
	return int(emu.GetRegion())
}

// GetFPS returns the frames per second for the current emulator state.
func GetFPS() int {
	if emu == nil {
		return 60
	}
	return emu.GetTiming().FPS
}

// DetectRegionFromPath detects the region for a ROM file (0=NTSC, 1=PAL).
func DetectRegionFromPath(path string) int {
	if factory == nil {
		return 0
	}

	info := factory.SystemInfo()
	rom, _, err := romloader.Load(path, info.Extensions)
	if err != nil {
		return 0
	}

	region, _ := factory.DetectRegion(rom)
	return int(region)
}

// HasSaveStates returns whether the emulator supports save states.
func HasSaveStates() bool {
	return saveStater != nil
}

// SaveState creates a save state. Returns true on success.
func SaveState() bool {
	if saveStater == nil {
		return false
	}
	data, err := saveStater.Serialize()
	if err != nil {
		stateData = nil
		return false
	}
	stateData = data
	return true
}

// StateLen returns the length of the last saved state.
func StateLen() int {
	return len(stateData)
}

// StateByte returns a single byte from the saved state at index i.
func StateByte(i int) int {
	if i < 0 || i >= len(stateData) {
		return 0
	}
	return int(stateData[i])
}

// LoadState loads a save state. Returns true on success.
func LoadState(data []byte) bool {
	if saveStater == nil {
		return false
	}
	return saveStater.Deserialize(data) == nil
}

// HasSRAM returns whether the current ROM uses battery-backed save.
func HasSRAM() bool {
	return batterySaver != nil && batterySaver.HasSRAM()
}

// PrepareSRAM copies SRAM to internal buffer.
func PrepareSRAM() {
	if batterySaver == nil {
		return
	}
	sramData = batterySaver.GetSRAM()
}

// SRAMLen returns the SRAM length.
func SRAMLen() int {
	return len(sramData)
}

// SRAMByte returns a single byte from SRAM at index i.
func SRAMByte(i int) int {
	if i < 0 || i >= len(sramData) {
		return 0
	}
	return int(sramData[i])
}

// LoadSRAM loads SRAM data into the emulator.
func LoadSRAM(data []byte) {
	if batterySaver != nil {
		batterySaver.SetSRAM(data)
	}
}

// ExtractAndStoreROM extracts a ROM from an archive, calculates its CRC32,
// and stores it as {CRC32}.{first extension} in destDir.
// Returns JSON with "crc" (hex string) and "name" (ROM filename without extension).
func ExtractAndStoreROM(srcPath, destDir string) (string, error) {
	if factory == nil {
		return "", fmt.Errorf("no factory registered")
	}

	info := factory.SystemInfo()
	if len(info.Extensions) == 0 {
		return "", fmt.Errorf("no extensions configured")
	}

	rom, romFilename, err := romloader.Load(srcPath, info.Extensions)
	if err != nil {
		return "", fmt.Errorf("failed to load ROM: %w", err)
	}

	crc := crc32.ChecksumIEEE(rom)
	crcHex := fmt.Sprintf("%08X", crc)

	// Strip extension from ROM filename for display name
	romName := strings.TrimSuffix(romFilename, filepath.Ext(romFilename))

	ext := info.Extensions[0]
	destPath := filepath.Join(destDir, crcHex+ext)

	// Skip write if file already exists
	if _, err := os.Stat(destPath); err == nil {
		return extractResultJSON(crcHex, romName), nil
	}

	if err := os.WriteFile(destPath, rom, 0644); err != nil {
		return "", fmt.Errorf("failed to write ROM: %w", err)
	}

	return extractResultJSON(crcHex, romName), nil
}

func extractResultJSON(crc, name string) string {
	result := struct {
		CRC  string `json:"crc"`
		Name string `json:"name"`
	}{CRC: crc, Name: name}
	data, _ := json.Marshal(result)
	return string(data)
}

// GetCRC32FromPath calculates the CRC32 checksum of a ROM file.
// Returns -1 on error.
func GetCRC32FromPath(path string) int64 {
	if factory == nil {
		return -1
	}

	info := factory.SystemInfo()
	rom, _, err := romloader.Load(path, info.Extensions)
	if err != nil {
		return -1
	}

	return int64(crc32.ChecksumIEEE(rom))
}

// SetOption applies a core option change to the emulator.
func SetOption(key string, value string) {
	if emu != nil {
		emu.SetOption(key, value)
	}
}
