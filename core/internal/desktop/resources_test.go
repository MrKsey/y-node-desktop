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

// A resource the user adds is never built in, whatever the file said before.
func TestSaveServiceKeepsAUserEntryPlain(t *testing.T) {
	isolateConfig(t)
	a := &App{cfg: DefaultConfig()}
	a.cfg.normalise()
	saved, err := a.SaveService(ServiceEntry{Title: "2ip", URL: "https://2ip.io"})
	if err != nil {
		t.Fatal(err)
	}
	if saved.BuiltIn {
		t.Fatal("a new resource is marked as built in")
	}
	for _, entry := range a.Services() {
		if entry.URL == "https://2ip.io" && entry.BuiltIn {
			t.Fatalf("%s is shown as built in", entry.ID)
		}
	}
}

// A stale "builtIn" value in the file must not turn a user entry into a
// catalogue one.
func TestWithBuiltInServicesClearsAStaleFlag(t *testing.T) {
	got := withBuiltInServices([]ServiceEntry{
		{ID: "user:https://2ip.io", Title: "2ip", URL: "https://2ip.io", BuiltIn: true},
	}, nil)
	for _, entry := range got {
		if entry.URL == "https://2ip.io" {
			if entry.BuiltIn {
				t.Fatal("the stale flag survived the merge")
			}
			return
		}
	}
	t.Fatal("the user entry is missing")
}

// Editing a built-in into another address makes it a user resource: the badge
// belongs to the catalogue, and the original default goes to the hidden list.
func TestEditingABuiltInIntoAnotherAddressDropsTheBadge(t *testing.T) {
	isolateConfig(t)
	a := &App{cfg: DefaultConfig()}
	a.cfg.normalise()
	saved, err := a.SaveService(ServiceEntry{
		ID:    "builtin:myip",
		Title: "2ip",
		URL:   "https://2ip.io",
	})
	if err != nil {
		t.Fatal(err)
	}
	if saved.BuiltIn {
		t.Fatalf("%s still carries the built-in badge", saved.ID)
	}
	if saved.ID == "builtin:myip" {
		t.Fatal("the catalogue id was kept")
	}
	hidden := a.HiddenServices()
	found := false
	for _, id := range hidden {
		if id == "builtin:myip" {
			found = true
		}
	}
	if !found {
		t.Fatalf("the original default is not hidden: %v", hidden)
	}
	for _, entry := range a.Services() {
		if entry.ID == "builtin:myip" {
			t.Fatal("the original default is still in the list")
		}
		if entry.URL == "https://2ip.io" && entry.BuiltIn {
			t.Fatal("the edited resource is shown as built in")
		}
	}
}

// A file written by an older build keeps the catalogue id on an edited entry.
// The migration in normalise() has to repair it, or the badge comes back.
func TestNormaliseDemotesAnEditedCatalogueEntry(t *testing.T) {
	isolateConfig(t)
	cfg := DefaultConfig()
	for index, entry := range cfg.Services {
		if entry.ID == "builtin:myip" {
			cfg.Services[index].URL = "https://2ip.io"
			cfg.Services[index].Title = "2ip"
			cfg.Services[index].BuiltIn = true
		}
	}
	cfg.normalise()
	for _, entry := range cfg.Services {
		if entry.URL == "https://2ip.io" {
			if entry.BuiltIn {
				t.Fatalf("%s still carries the badge after normalise", entry.ID)
			}
			if entry.ID == "builtin:myip" {
				t.Fatal("the catalogue id survived the migration")
			}
		}
	}
	hidden := false
	for _, id := range cfg.HiddenServices {
		if id == "builtin:myip" {
			hidden = true
		}
	}
	if !hidden {
		t.Fatalf("the original default is not hidden: %v", cfg.HiddenServices)
	}
}
