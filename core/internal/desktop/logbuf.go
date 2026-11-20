package desktop

import (
	"fmt"
	"sync"
	"time"
)

// LogLine is one entry of the in-memory log the UI reads.
type LogLine struct {
	Time    time.Time `json:"time"`
	Level   string    `json:"level"`
	Message string    `json:"message"`
}

// LogBuffer keeps the last lines of the core so the desktop window can show
// them without a second log file. It implements yggnode.Logger.
type LogBuffer struct {
	mu      sync.Mutex
	lines   []LogLine
	limit   int
	enabled bool
}

func NewLogBuffer(limit int) *LogBuffer {
	if limit < 50 {
		limit = 50
	}
	return &LogBuffer{limit: limit, enabled: true}
}

// SetEnabled turns the in-memory log on or off. Turning it off drops the
// buffered lines as well, so a disabled log cannot be read from the window.
func (b *LogBuffer) SetEnabled(enabled bool) {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.enabled = enabled
	if !enabled {
		b.lines = nil
	}
}

// Enabled reports whether new lines are kept.
func (b *LogBuffer) Enabled() bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.enabled
}

// Log implements yggnode.Logger.
func (b *LogBuffer) Log(level, message string) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if !b.enabled {
		return
	}
	b.lines = append(b.lines, LogLine{Time: time.Now(), Level: level, Message: message})
	if len(b.lines) > b.limit {
		b.lines = append([]LogLine(nil), b.lines[len(b.lines)-b.limit:]...)
	}
}

// Infof writes an informational line from the desktop layer.
func (b *LogBuffer) Infof(format string, args ...any) {
	b.Log("info", fmt.Sprintf(format, args...))
}

// Warnf writes a warning from the desktop layer.
func (b *LogBuffer) Warnf(format string, args ...any) {
	b.Log("warn", fmt.Sprintf(format, args...))
}

// List returns a copy of the buffer.
func (b *LogBuffer) List() []LogLine {
	b.mu.Lock()
	defer b.mu.Unlock()
	out := make([]LogLine, len(b.lines))
	copy(out, b.lines)
	return out
}
