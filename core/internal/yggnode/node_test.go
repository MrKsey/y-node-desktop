package yggnode

import (
	"context"
	"testing"
	"time"
)

type testLogger struct{}

func (testLogger) Log(string, string) {}

// A cancelled session must not start a probe node: Disconnect calls cancel
// before it stops the tunnel, and a supervisor round that was already waiting
// for the ticker must return at once.
func TestProbePeersContextStopsWhenCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	started := time.Now()
	out := ProbePeersContext(ctx, `["tls://127.0.0.1:1"]`, 5000, testLogger{})
	if out != "[]" {
		t.Fatalf("probe returned %q, want an empty list", out)
	}
	if elapsed := time.Since(started); elapsed > time.Second {
		t.Fatalf("a cancelled probe took %s", elapsed)
	}
}
