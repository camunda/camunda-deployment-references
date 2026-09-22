package test

import "testing"

// The engine inserts `physicalTenant` between `id` and `state`, so the literal
// `"id":8,"state":"ACTIVE"` no longer appears in a topology response even when
// partition 8 is present and active. That is what turned the failback broker
// addition red: the cluster had accepted the change, and the assertion was
// reading the serialisation rather than the state.
func TestTopologyHasActiveEntryToleratesInsertedFields(t *testing.T) {
	t.Parallel()

	const withTenant = `{"expectedTopology":[{"id":0,"state":"ACTIVE","partitions":[` +
		`{"id":8,"physicalTenant":"default","state":"ACTIVE","priority":3}]}]}`
	const withoutTenant = `{"expectedTopology":[{"id":0,"state":"ACTIVE","partitions":[` +
		`{"id":8,"state":"ACTIVE","priority":3}]}]}`

	for name, body := range map[string]string{
		"with physicalTenant":    withTenant,
		"without physicalTenant": withoutTenant,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if !topologyHasActiveEntry(body, 8, "ACTIVE") {
				t.Fatalf("expected partition 8 to read as ACTIVE in:\n%s", body)
			}
		})
	}
}

// A response that never mentions the entry, or that mentions it in another
// state, must read false — otherwise the scaling check passes on a cluster that
// never accepted the change.
func TestTopologyHasActiveEntryRejectsAbsentOrInactive(t *testing.T) {
	t.Parallel()

	for name, body := range map[string]string{
		"entry absent":   `{"expectedTopology":[{"id":0,"state":"ACTIVE","partitions":[{"id":7,"state":"ACTIVE"}]}]}`,
		"entry inactive": `{"expectedTopology":[{"id":0,"state":"ACTIVE","partitions":[{"id":8,"state":"LEAVING"}]}]}`,
		"malformed":      `not json`,
		"empty body":     ``,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if topologyHasActiveEntry(body, 8, "ACTIVE") {
				t.Fatalf("expected %s to read false, got true for:\n%s", name, body)
			}
		})
	}
}
