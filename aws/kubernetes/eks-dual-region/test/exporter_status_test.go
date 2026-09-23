package test

import "testing"

// The engine added a `physicalTenant` field to every entry of
// GET /actuator/exporters. The failover checks used to compare the serialised
// object byte for byte, so the extra field made a disabled exporter read as
// still enabled: the POST succeeded, the poll never matched, and the suite
// failed on its retry budget with the cluster in the state it asked for.
func TestExporterStatusIsToleratesNewResponseFields(t *testing.T) {
	t.Parallel()

	const withTenant = `[{"exporterId":"camundaregion0","status":"ENABLED","physicalTenant":"default"},` +
		`{"exporterId":"camundaregion1","status":"DISABLED","physicalTenant":"default"}]`
	const withoutTenant = `[{"exporterId":"camundaregion0","status":"ENABLED"},` +
		`{"exporterId":"camundaregion1","status":"DISABLED"}]`

	for name, body := range map[string]string{
		"with physicalTenant":    withTenant,
		"without physicalTenant": withoutTenant,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if !exporterStatusIs(body, "camundaregion1", "DISABLED") {
				t.Fatalf("expected camundaregion1 to read as DISABLED in:\n%s", body)
			}
			if !exporterStatusIs(body, "camundaregion0", "ENABLED") {
				t.Fatalf("expected camundaregion0 to read as ENABLED in:\n%s", body)
			}
			if exporterStatusIs(body, "camundaregion1", "ENABLED") {
				t.Fatalf("expected camundaregion1 not to read as ENABLED in:\n%s", body)
			}
		})
	}
}

// An exporter the response does not mention has no status, and a body that is
// not the expected list is not evidence of anything. Both have to read false
// rather than true, or a failover check passes on a response it never parsed.
func TestExporterStatusIsRejectsUnusableResponses(t *testing.T) {
	t.Parallel()

	for name, body := range map[string]string{
		"exporter absent": `[{"exporterId":"camundaregion0","status":"ENABLED"}]`,
		"empty list":      `[]`,
		"not a list":      `{"exporterId":"camundaregion1","status":"DISABLED"}`,
		"malformed":       `not json`,
		"empty body":      ``,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			if exporterStatusIs(body, "camundaregion1", "DISABLED") {
				t.Fatalf("expected %s to read false, got true for:\n%s", name, body)
			}
		})
	}
}

// Every physical tenant carries its own entry for the same exporter, so one
// tenant still exporting means the exporter is not disabled cluster-wide.
func TestExporterStatusIsRequiresEveryTenantToAgree(t *testing.T) {
	t.Parallel()

	const mixed = `[{"exporterId":"camundaregion1","status":"DISABLED","physicalTenant":"default"},` +
		`{"exporterId":"camundaregion1","status":"ENABLED","physicalTenant":"other"}]`

	if exporterStatusIs(mixed, "camundaregion1", "DISABLED") {
		t.Fatalf("expected a tenant still ENABLED to prevent a DISABLED verdict in:\n%s", mixed)
	}
}
