package desktop

import (
	"encoding/json"
	"testing"
)

func TestWithBuiltInServicesRestoresTheCatalogue(t *testing.T) {
	got := withBuiltInServices(nil, nil)
	if len(got) != len(builtInServices()) {
		t.Fatalf("services = %d, want %d", len(got), len(builtInServices()))
	}
	for _, entry := range got {
		if !entry.BuiltIn {
			t.Fatalf("%s is not marked as built-in", entry.ID)
		}
	}
}

func TestWithBuiltInServicesKeepsTheOrderAndTheFlag(t *testing.T) {
	current := []ServiceEntry{
		{ID: "user:mine", Title: "Mine", URL: "http://[200::1]/"},
		{ID: "builtin:forum", Title: "Forum in Yggdrasil", URL: "http://[21a::1]/"},
	}
	got := withBuiltInServices(current, nil)
	if got[0].ID != "builtin:directory" {
		t.Fatalf("the missing default does not lead the list: %+v", got[0])
	}
	for _, entry := range got {
		if entry.ID == "builtin:forum" && !entry.BuiltIn {
			t.Fatal("a saved built-in lost its flag")
		}
	}
	// The user entry keeps its place right after the defaults that came back.
	if got[len(got)-2].ID != "user:mine" {
		t.Fatalf("user entry moved: %+v", got[len(got)-2])
	}
}

func TestWithBuiltInServicesSkipsTheHiddenOnes(t *testing.T) {
	current := []ServiceEntry{
		{ID: "user:mine", Title: "Mine", URL: "http://[200::1]/"},
	}
	got := withBuiltInServices(current, []string{"builtin:directory", "builtin:myip"})
	for _, entry := range got {
		if entry.ID == "builtin:directory" || entry.ID == "builtin:myip" {
			t.Fatalf("%s came back although it was deleted", entry.ID)
		}
	}
	if len(got) != len(builtInServices())-2+1 {
		t.Fatalf("services = %d, want %d", len(got), len(builtInServices())-1)
	}
}

func TestHiddenBuiltInStaysDeletedAfterARestart(t *testing.T) {
	cfg := DefaultConfig()
	cfg.normalise()
	// The user deletes one default on the Services page.
	next := make([]ServiceEntry, 0, len(cfg.Services))
	for _, entry := range cfg.Services {
		if entry.ID == "builtin:forum" {
			cfg.HiddenServices = append(cfg.HiddenServices, entry.ID)
			continue
		}
		next = append(next, entry)
	}
	cfg.Services = next

	raw, err := json.Marshal(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var restored Config
	if err := json.Unmarshal(raw, &restored); err != nil {
		t.Fatal(err)
	}
	restored.normalise()
	for _, entry := range restored.Services {
		if entry.ID == "builtin:forum" {
			t.Fatal("a deleted built-in came back after a restart")
		}
	}
	if len(restored.HiddenServices) != 1 || restored.HiddenServices[0] != "builtin:forum" {
		t.Fatalf("hidden = %v", restored.HiddenServices)
	}
}

func TestReorderServicesKeepsEveryEntryInTheGivenOrder(t *testing.T) {
	isolateConfig(t)
	a := &App{cfg: DefaultConfig()}
	a.cfg.normalise()
	// The window orders the merged list, including a default the file may not
	// hold yet.
	all := a.Services()
	ids := make([]string, 0, len(all))
	for _, entry := range all {
		ids = append([]string{entry.ID}, ids...)
	}
	if err := a.ReorderServices(ids); err != nil {
		t.Fatal(err)
	}
	got := a.Services()
	if len(got) != len(all) {
		t.Fatalf("services = %d, want %d", len(got), len(all))
	}
	for index, id := range ids {
		if got[index].ID != id {
			t.Fatalf("position %d is %s, want %s", index, got[index].ID, id)
		}
	}
}

func TestRemoveServicesHidesTheBuiltInsAndRestoreBringsThemBack(t *testing.T) {
	isolateConfig(t)
	a := &App{cfg: DefaultConfig()}
	a.cfg.normalise()
	if _, err := a.RemoveServices([]string{"builtin:forum", "builtin:myip"}); err != nil {
		t.Fatal(err)
	}
	got := a.Services()
	for _, entry := range got {
		if entry.ID == "builtin:forum" || entry.ID == "builtin:myip" {
			t.Fatalf("%s was not deleted", entry.ID)
		}
	}
	if hidden := a.HiddenServices(); len(hidden) != 2 {
		t.Fatalf("hidden = %v", hidden)
	}
	// The file the next start reads keeps the deletion.
	loaded, err := loadConfig()
	if err != nil {
		t.Fatal(err)
	}
	loaded.normalise()
	for _, entry := range loaded.Services {
		if entry.ID == "builtin:forum" {
			t.Fatal("a deleted built-in came back from the file")
		}
	}
	if err := a.RestoreBuiltIns(); err != nil {
		t.Fatal(err)
	}
	if hidden := a.HiddenServices(); len(hidden) != 0 {
		t.Fatalf("hidden after restore = %v", hidden)
	}
	if len(a.Services()) != len(builtInServices()) {
		t.Fatalf("services after restore = %d", len(a.Services()))
	}
}

// isolateConfig points the configuration of the core at a temporary directory:
// the tests that save a configuration must never touch the real one.
func isolateConfig(t *testing.T) {
	t.Helper()
	t.Setenv("APPDATA", t.TempDir())
	t.Setenv("XDG_CONFIG_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())
}

func TestBuiltInServicesSurviveAConfigRoundTrip(t *testing.T) {
	cfg := DefaultConfig()
	cfg.normalise()
	raw, err := json.Marshal(cfg)
	if err != nil {
		t.Fatal(err)
	}
	var restored Config
	if err := json.Unmarshal(raw, &restored); err != nil {
		t.Fatal(err)
	}
	restored.normalise()
	if len(restored.Services) != len(builtInServices()) {
		t.Fatalf("services after a round trip = %d", len(restored.Services))
	}
	for _, entry := range restored.Services {
		if !entry.BuiltIn {
			t.Fatalf("%s lost its built-in flag", entry.ID)
		}
	}
}
