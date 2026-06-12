package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func testServer(t *testing.T) (*AppServer, string) {
	t.Helper()
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	repoRoot := filepath.Dir(cwd)
	dataDir := t.TempDir()
	server := NewAppServer(dataDir, filepath.Join(repoRoot, "ocg", "registry"), filepath.Join(repoRoot, "web", "src"))
	return server, dataDir
}

func requestJSON(t *testing.T, handler http.Handler, method, path string, body any) (int, map[string]any) {
	t.Helper()
	status, parsed, err := requestJSONResult(handler, method, path, body)
	if err != nil {
		t.Fatal(err)
	}
	return status, parsed
}

func requestJSONResult(handler http.Handler, method, path string, body any) (int, map[string]any, error) {
	var payload bytes.Buffer
	if body != nil {
		if err := json.NewEncoder(&payload).Encode(body); err != nil {
			return 0, nil, err
		}
	}
	req := httptest.NewRequest(method, path, &payload)
	if body != nil {
		req.Header.Set("content-type", "application/json")
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	var parsed map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &parsed); err != nil {
		return rec.Code, nil, fmt.Errorf("invalid json response %d: %s", rec.Code, rec.Body.String())
	}
	return rec.Code, parsed, nil
}

type expectedApp struct {
	AppID           string
	OcgAppID        string
	DisplayName     string
	Endpoint        string
	Transport       string
	BundleID        string
	Platform        string
	RegistrySource  string
	CapabilityID    string
	Risk            string
	Consent         string
	RequiresPayment bool
	Asset           any
	URLScheme       string
	RoutingHint     string
	InputSchema     []string
	ResultSchema    []string
}

func appMap(rawApps []any) map[string]map[string]any {
	apps := map[string]map[string]any{}
	for _, raw := range rawApps {
		app := raw.(map[string]any)
		apps[fmt.Sprint(app["appId"])] = app
	}
	return apps
}

func stringSlice(raw any) []string {
	values, _ := raw.([]any)
	output := make([]string, 0, len(values))
	for _, value := range values {
		output = append(output, fmt.Sprint(value))
	}
	return output
}

func equalStrings(left, right []string) bool {
	if len(left) != len(right) {
		return false
	}
	for idx := range left {
		if left[idx] != right[idx] {
			return false
		}
	}
	return true
}

func assertDiscoveryApp(t *testing.T, app map[string]any, expected expectedApp) {
	t.Helper()
	if app == nil {
		t.Fatalf("missing app %s", expected.AppID)
	}
	for key, want := range map[string]any{
		"schemaVersion":  acpSchemaVersion,
		"appId":          expected.AppID,
		"ocgAppId":       expected.OcgAppID,
		"displayName":    expected.DisplayName,
		"publisher":      "MeshKit Samples",
		"acpEndpoint":    expected.Endpoint,
		"mcpTransport":   expected.Transport,
		"bundleId":       expected.BundleID,
		"platform":       expected.Platform,
		"registrySource": expected.RegistrySource,
	} {
		if app[key] != want {
			t.Fatalf("%s %s = %#v, want %#v in %#v", expected.AppID, key, app[key], want, app)
		}
	}
	capabilities := app["capabilities"].([]any)
	if len(capabilities) != 1 {
		t.Fatalf("%s capabilities = %#v", expected.AppID, capabilities)
	}
	capability := capabilities[0].(map[string]any)
	for key, want := range map[string]any{
		"id":              expected.CapabilityID,
		"risk":            expected.Risk,
		"consent":         expected.Consent,
		"requiresPayment": expected.RequiresPayment,
		"asset":           expected.Asset,
		"urlScheme":       expected.URLScheme,
		"routingHint":     expected.RoutingHint,
	} {
		if capability[key] != want {
			t.Fatalf("%s capability %s = %#v, want %#v in %#v", expected.AppID, key, capability[key], want, capability)
		}
	}
	if fmt.Sprint(capability["displayName"]) == "" {
		t.Fatalf("%s capability missing displayName: %#v", expected.AppID, capability)
	}
	if got := stringSlice(capability["inputSchema"]); !equalStrings(got, expected.InputSchema) {
		t.Fatalf("%s inputSchema = %#v, want %#v", expected.AppID, got, expected.InputSchema)
	}
	if got := stringSlice(capability["resultSchema"]); !equalStrings(got, expected.ResultSchema) {
		t.Fatalf("%s resultSchema = %#v, want %#v", expected.AppID, got, expected.ResultSchema)
	}
}

func TestGoServerSupportsSuperappAPIParity(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()

	status, discovery := requestJSON(t, handler, http.MethodGet, "/api/acp/apps", nil)
	if status != http.StatusOK {
		t.Fatalf("discovery status = %d", status)
	}
	if discovery["registryMode"] != "signed-ocg-registry" {
		t.Fatalf("registryMode = %v", discovery["registryMode"])
	}
	trust := discovery["registryTrust"].(map[string]any)
	if trust["verifiedCount"].(float64) != 2 {
		t.Fatalf("verifiedCount = %v", trust["verifiedCount"])
	}
	apps := discovery["apps"].([]any)
	if len(apps) != 3 {
		t.Fatalf("apps len = %d", len(apps))
	}
	if apps[0].(map[string]any)["displayName"] != "HermesChat" || apps[1].(map[string]any)["displayName"] != "MintNotes" || apps[2].(map[string]any)["displayName"] != "DailyMart" {
		t.Fatalf("unexpected apps: %#v", apps)
	}

	status, preference := requestJSON(t, handler, http.MethodPost, "/api/preferences", map[string]any{
		"userId": "local-user", "agentId": "agent.meshkit-superapp", "key": "privacy_policy",
		"value": "cart/address/user/consent details stay off-chain", "source": "go-api-test",
	})
	if status != http.StatusCreated {
		t.Fatalf("preference status = %d body=%#v", status, preference)
	}
	if preference["preference"].(map[string]any)["key"] != "privacy_policy" {
		t.Fatalf("preference key = %#v", preference)
	}

	status, paid := requestJSON(t, handler, http.MethodPost, "/api/execute", map[string]any{
		"capabilityId": "grocery.purchase_essentials", "amount": 42, "requestId": "req-go-paid",
	})
	if status != http.StatusCreated {
		t.Fatalf("paid status = %d body=%#v", status, paid)
	}
	paidRoute := paid["routeDecision"].(map[string]any)
	paidRecord := paid["transactionRecord"].(map[string]any)
	if paidRoute["route"] != "onchain" || paidRoute["appId"] != "app.dailymart" || paidRecord["recordType"] != "onchain-sim" {
		t.Fatalf("bad paid route %#v record %#v", paidRoute, paidRecord)
	}
	if paidRecord["txHash"] == "" {
		t.Fatalf("paid txHash missing")
	}

	status, unpaid := requestJSON(t, handler, http.MethodPost, "/api/execute", map[string]any{
		"capabilityId": "notes.append_note", "amount": 0, "requestId": "req-go-unpaid",
	})
	if status != http.StatusCreated {
		t.Fatalf("unpaid status = %d body=%#v", status, unpaid)
	}
	unpaidRoute := unpaid["routeDecision"].(map[string]any)
	unpaidRecord := unpaid["transactionRecord"].(map[string]any)
	if unpaidRoute["route"] != "offchain" || unpaidRecord["recordType"] != "app-to-app-url-scheme" || unpaidRecord["txHash"] != "" {
		t.Fatalf("bad unpaid route %#v record %#v", unpaidRoute, unpaidRecord)
	}

	status, settlements := requestJSON(t, handler, http.MethodGet, "/api/settlements", nil)
	if status != http.StatusOK {
		t.Fatalf("settlements status = %d", status)
	}
	ledger := settlements["settlementLedger"].(map[string]any)
	entries := ledger["entries"].([]any)
	if len(entries) != 1 || entries[0].(map[string]any)["requestId"] != "req-go-paid" {
		t.Fatalf("settlement entries = %#v", entries)
	}
	summary := ledger["summary"].(map[string]any)
	if summary["totalConfirmed"].(float64) != 42 || summary["totalDebits"].(float64) != 42 {
		t.Fatalf("settlement summary = %#v", summary)
	}

	status, invalid := requestJSON(t, handler, http.MethodPost, "/api/execute", map[string]any{"capabilityId": "missing.capability", "amount": 1})
	if status != http.StatusBadRequest {
		t.Fatalf("invalid status = %d body=%#v", status, invalid)
	}
}

func TestAgentChatRunsRealConversationThroughACPTools(t *testing.T) {
	server, _ := testServer(t)
	var calls int
	openAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected OpenAI path %s", r.URL.Path)
		}
		var request map[string]any
		if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
			t.Fatalf("decode OpenAI request: %v", err)
		}
		if request["tool_choice"] != "auto" {
			t.Fatalf("tool_choice = %v", request["tool_choice"])
		}
		tools := request["tools"].([]any)
		if len(tools) < 5 {
			t.Fatalf("tools len = %d", len(tools))
		}
		calls++
		w.Header().Set("content-type", "application/json")
		switch calls {
		case 1:
			writeJSON(w, http.StatusOK, map[string]any{"choices": []any{map[string]any{"message": map[string]any{
				"role": "assistant",
				"tool_calls": []any{
					mockToolCall("call-pref-1", "remember_preference", map[string]any{"key": "low_sugar_groceries", "value": "User prefers low-sugar groceries."}),
					mockToolCall("call-pref-2", "remember_preference", map[string]any{"key": "on_chain_okrw_proof", "value": "Paid purchases require on-chain OKRW proof."}),
					mockToolCall("call-note", "invoke__notes__append_note", map[string]any{"amount": 0, "userSummary": "Append requested note", "noteText": "buy bananas first", "noteRef": "bananas"}),
					mockToolCall("call-grocery", "invoke__grocery__purchase_essentials", map[string]any{"amount": 42, "userSummary": "Buy DailyMart essentials", "items": []string{"essentials"}, "budgetOkrw": 42}),
					mockToolCall("call-ledger", "get_settlement_ledger", map[string]any{}),
				},
			}}}})
		case 2:
			writeJSON(w, http.StatusOK, map[string]any{"choices": []any{map[string]any{"message": map[string]any{
				"role":    "assistant",
				"content": "Saved preferences, appended `buy bananas first` in MintNotes, bought DailyMart essentials for 42 OKRW, and confirmed settlement proof on-chain.",
			}}}})
		default:
			t.Fatalf("unexpected OpenAI call %d", calls)
		}
	}))
	defer openAI.Close()
	t.Setenv("OPENAI_API_KEY", "test-key")
	t.Setenv("OPENAI_BASE_URL", openAI.URL+"/v1")
	t.Setenv("OPENAI_MODEL", "mock-chat-model")

	status, response := requestJSON(t, server.Routes(), http.MethodPost, "/api/agent-chat", map[string]any{
		"messages": []any{
			map[string]any{"role": "user", "content": "Remember low-sugar groceries and on-chain OKRW proof. Append a note saying \"buy bananas first\" and buy DailyMart essentials for 42 OKRW."},
		},
	})
	if status != http.StatusOK {
		t.Fatalf("agent chat status = %d response=%#v", status, response)
	}
	if response["schemaVersion"] != "meshkit-agent-chat-response/v1" {
		t.Fatalf("schemaVersion = %v", response["schemaVersion"])
	}
	assistant := response["assistant"].(map[string]any)
	if !strings.Contains(fmt.Sprint(assistant["content"]), "buy bananas first") || !strings.Contains(fmt.Sprint(assistant["content"]), "42 OKRW") {
		t.Fatalf("assistant content = %#v", assistant)
	}
	results := response["toolResults"].([]any)
	if len(results) != 5 {
		t.Fatalf("toolResults len = %d results=%#v", len(results), results)
	}
	state := response["state"].(map[string]any)
	executions := state["executionRecords"].([]any)
	if len(executions) != 2 {
		t.Fatalf("executions = %#v", executions)
	}
	ledger := state["settlementLedger"].(map[string]any)
	summary := ledger["summary"].(map[string]any)
	if summary["totalConfirmed"].(float64) != 42 {
		t.Fatalf("settlement summary = %#v", summary)
	}
	if calls != 2 {
		t.Fatalf("OpenAI calls = %d", calls)
	}
}

func mockToolCall(id, name string, arguments map[string]any) map[string]any {
	encoded, _ := json.Marshal(arguments)
	return map[string]any{
		"id":   id,
		"type": "function",
		"function": map[string]any{
			"name":      name,
			"arguments": string(encoded),
		},
	}
}

func TestAgentClientProtocolDiscoveryContract(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()

	status, discovery := requestJSON(t, handler, http.MethodGet, "/api/acp/apps", nil)
	if status != http.StatusOK {
		t.Fatalf("discovery status = %d", status)
	}
	if discovery["schemaVersion"] != "meshkit-acp-discovery-response/v1" {
		t.Fatalf("schemaVersion = %v", discovery["schemaVersion"])
	}
	if discovery["registryMode"] != "signed-ocg-registry" {
		t.Fatalf("registryMode = %v", discovery["registryMode"])
	}
	if discovery["registryError"] != nil {
		t.Fatalf("registryError = %v", discovery["registryError"])
	}
	if got := stringSlice(discovery["registryFiles"]); !equalStrings(got, []string{"dailymart.signed.ocg.json", "mint-notes.signed.ocg.json"}) {
		t.Fatalf("registryFiles = %#v", got)
	}
	trust := discovery["registryTrust"].(map[string]any)
	if trust["signed"] != true || trust["verifiedCount"].(float64) != 2 || trust["issuer"] != "https://registry.meshkit.ai" {
		t.Fatalf("registryTrust = %#v", trust)
	}
	if got := stringSlice(trust["keyIds"]); !equalStrings(got, []string{"ocg-registry-test-2026-05"}) {
		t.Fatalf("registryTrust keyIds = %#v", got)
	}

	apps := appMap(discovery["apps"].([]any))
	assertDiscoveryApp(t, apps["app.hermes-chat"], expectedApp{
		AppID: "app.hermes-chat", OcgAppID: "app.hermes-chat", DisplayName: "HermesChat",
		Endpoint: "acp://hermes-chat/apps", Transport: "app-to-app-url-scheme", BundleID: "ai.meshkit.sample.hermeschat",
		Platform: "local", RegistrySource: "local-fixture", CapabilityID: "agent.plan_trip", Risk: "read_only",
		Consent: "remember_for_app", RequiresPayment: false, Asset: nil, URLScheme: "hermeschat://mesh/invoke",
		RoutingHint: "offchain_app_call", InputSchema: []string{"intent", "preference_refs"}, ResultSchema: []string{"plan", "recommended_app_ids"},
	})
	assertDiscoveryApp(t, apps["app.mint-notes"], expectedApp{
		AppID: "app.mint-notes", OcgAppID: "ai.meshkit.sample.notes", DisplayName: "MintNotes",
		Endpoint: "acp://mint-notes/apps", Transport: "app-to-app-url-scheme", BundleID: "ai.meshkit.sample.mintnotes",
		Platform: "android", RegistrySource: "signed-ocg-registry", CapabilityID: "notes.append_note", Risk: "write:user_content",
		Consent: "per_invocation", RequiresPayment: false, Asset: nil, URLScheme: "mintnotes://mesh/invoke",
		RoutingHint: "offchain_app_call", InputSchema: []string{"note_ref", "text"}, ResultSchema: []string{"status", "note_ref"},
	})
	assertDiscoveryApp(t, apps["app.dailymart"], expectedApp{
		AppID: "app.dailymart", OcgAppID: "ai.meshkit.sample.dailymart", DisplayName: "DailyMart",
		Endpoint: "acp://dailymart/apps", Transport: "app-to-app-url-scheme", BundleID: "ai.meshkit.sample.dailymart",
		Platform: "android", RegistrySource: "signed-ocg-registry", CapabilityID: "grocery.purchase_essentials", Risk: "spend:money",
		Consent: "budgeted_per_invocation", RequiresPayment: true, Asset: "OKRW", URLScheme: "dailymart://mesh/invoke",
		RoutingHint: "onchain_payment", InputSchema: []string{"items", "max_budget_krw", "delivery_window", "payment_method"}, ResultSchema: []string{"status", "order_id"},
	})
	for _, appID := range []string{"app.mint-notes", "app.dailymart"} {
		verification := apps[appID]["registrySignatureVerification"].(map[string]any)
		if verification["status"] != "verified" || verification["kid"] != "ocg-registry-test-2026-05" {
			t.Fatalf("%s signature verification = %#v", appID, verification)
		}
		if apps[appID]["registrySignature"] == nil || apps[appID]["trust"] == nil {
			t.Fatalf("%s missing trust/signature material: %#v", appID, apps[appID])
		}
	}

	status, state := requestJSON(t, handler, http.MethodGet, "/api/superapp-state", nil)
	if status != http.StatusOK {
		t.Fatalf("state status = %d", status)
	}
	stateDiscovery := state["acpDiscovery"].(map[string]any)
	if stateDiscovery["registryMode"] != discovery["registryMode"] {
		t.Fatalf("state registryMode = %v discovery = %v", stateDiscovery["registryMode"], discovery["registryMode"])
	}
	if got := stringSlice(stateDiscovery["registryFiles"]); !equalStrings(got, stringSlice(discovery["registryFiles"])) {
		t.Fatalf("state registryFiles = %#v discovery = %#v", got, discovery["registryFiles"])
	}
	stateApps := appMap(state["apps"].([]any))
	for appID, app := range apps {
		if stateApps[appID]["acpEndpoint"] != app["acpEndpoint"] {
			t.Fatalf("state app %s endpoint = %v discovery endpoint = %v", appID, stateApps[appID]["acpEndpoint"], app["acpEndpoint"])
		}
		if stateApps[appID]["mcpTransport"] != app["mcpTransport"] {
			t.Fatalf("state app %s transport = %v discovery transport = %v", appID, stateApps[appID]["mcpTransport"], app["mcpTransport"])
		}
	}
}

func TestGoStoreSerializesConcurrentPaidAndUnpaidWrites(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()
	done := make(chan error, 2)
	go func() {
		status, _, err := requestJSONResult(handler, http.MethodPost, "/api/execute", map[string]any{"capabilityId": "grocery.purchase_essentials", "amount": 42, "requestId": "req-concurrent-paid"})
		if err == nil && status != http.StatusCreated {
			err = fmt.Errorf("paid status = %d", status)
		}
		done <- err
	}()
	go func() {
		status, _, err := requestJSONResult(handler, http.MethodPost, "/api/execute", map[string]any{"capabilityId": "notes.append_note", "amount": 0, "requestId": "req-concurrent-unpaid"})
		if err == nil && status != http.StatusCreated {
			err = fmt.Errorf("unpaid status = %d", status)
		}
		done <- err
	}()
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	_, state := requestJSON(t, handler, http.MethodGet, "/api/superapp-state", nil)
	records := state["executionRecords"].([]any)
	if len(records) != 2 {
		t.Fatalf("execution records = %#v", records)
	}
	ledger := state["settlementLedger"].(map[string]any)
	entries := ledger["entries"].([]any)
	if len(entries) != 1 || entries[0].(map[string]any)["requestId"] != "req-concurrent-paid" {
		t.Fatalf("settlement entries = %#v", entries)
	}
}

func TestGoMemoryNormalizesSeedAndStrippingMetadata(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()

	_, state := requestJSON(t, handler, http.MethodGet, "/api/superapp-state", nil)
	memory := state["memory"].(map[string]any)
	for _, raw := range memory["promotedMemory"].([]any) {
		entry := raw.(map[string]any)
		if entry["userId"] != defaultUserID || entry["agentId"] != defaultAgentID {
			t.Fatalf("seed memory ids not normalized: %#v", entry)
		}
	}

	status, response := requestJSON(t, handler, http.MethodPost, "/api/preferences", map[string]any{
		"key": "wrapped_policy", "value": "<memory-context>previous recall</memory-context>User prefers receipts for every order.", "source": "go-api-test",
	})
	if status != http.StatusCreated {
		t.Fatalf("wrapped preference status = %d body=%#v", status, response)
	}
	state = response["state"].(map[string]any)
	memory = state["memory"].(map[string]any)
	foundFiltered := false
	for _, raw := range memory["filteredEvents"].([]any) {
		event := raw.(map[string]any)
		if event["key"] == "wrapped_policy" {
			foundFiltered = true
			if event["recalledContextStripped"] != true {
				t.Fatalf("filtered event stripping flag = %#v", event)
			}
		}
	}
	if !foundFiltered {
		t.Fatal("wrapped_policy filtered event missing")
	}
	for _, raw := range memory["promotedMemory"].([]any) {
		entry := raw.(map[string]any)
		if entry["key"] == "wrapped_policy" {
			if strings.Contains(entry["content"].(string), "memory-context") {
				t.Fatalf("content was not stripped: %#v", entry)
			}
			hippocampus := entry["metadata"].(map[string]any)["hippocampus"].(map[string]any)
			if hippocampus["recalledContextStripped"] != true {
				t.Fatalf("memory stripping metadata = %#v", hippocampus)
			}
			return
		}
	}
	t.Fatal("wrapped_policy promoted memory missing")
}

func TestGoExecuteRejectsInvalidAmountsAndCapabilityAmountMismatches(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()
	cases := []map[string]any{
		{"capabilityId": "grocery.purchase_essentials"},
		{"capabilityId": "grocery.purchase_essentials", "amount": "abc"},
		{"capabilityId": "grocery.purchase_essentials", "amount": -1},
		{"capabilityId": "grocery.purchase_essentials", "amount": 0},
		{"capabilityId": "notes.append_note", "amount": 1},
	}
	for _, body := range cases {
		status, response := requestJSON(t, handler, http.MethodPost, "/api/execute", body)
		if status != http.StatusBadRequest {
			t.Fatalf("body %#v status = %d response=%#v", body, status, response)
		}
	}
	memory := createPreferenceMemory(samplePreferenceEvents())
	if _, err := routeExecution(fallbackApps(), memory, "notes.append_note", math.Inf(1)); err == nil {
		t.Fatal("routeExecution accepted non-finite amount")
	}
}

func TestGoRoutingPolicyUsesNodeContentPatternFallbacks(t *testing.T) {
	server, _ := testServer(t)
	handler := server.Routes()
	for _, body := range []map[string]any{
		{"key": "payment_proof_policy", "value": "payments should keep a receipt record", "source": "go-api-test"},
		{"key": "privacy_policy", "value": "share only what is necessary", "source": "go-api-test"},
	} {
		status, response := requestJSON(t, handler, http.MethodPost, "/api/preferences", body)
		if status != http.StatusCreated {
			t.Fatalf("preference status = %d body=%#v", status, response)
		}
	}
	status, response := requestJSON(t, handler, http.MethodPost, "/api/execute", map[string]any{
		"capabilityId": "grocery.purchase_essentials", "amount": 42, "requestId": "req-policy-fallback",
	})
	if status != http.StatusCreated {
		t.Fatalf("execute status = %d body=%#v", status, response)
	}
	policy := response["routeDecision"].(map[string]any)["appliedPolicy"].(map[string]any)
	if policy["paymentProof"] != "onchain-required-by-capability" {
		t.Fatalf("paymentProof = %#v", policy)
	}
	if policy["nonPaymentTransport"] != "offchain-app-to-app-mcp-default" {
		t.Fatalf("nonPaymentTransport = %#v", policy)
	}
	if policy["payloadPrivacy"] != "minimal-chain-visible-fields-only" {
		t.Fatalf("payloadPrivacy = %#v", policy)
	}
}

func TestSignedRegistryFailsClosedOnBadSignatureAndMalformedManifest(t *testing.T) {
	server, _ := testServer(t)
	registryDir := t.TempDir()
	writeTestJWKS(t, registryDir)
	writeJSONFile(t, filepath.Join(registryDir, "signed", "bad-signature.ocg.json"), validManifestWithSignature("bad-signature"))
	server.registryDir = registryDir
	discovery := server.loadAcpDiscovery()
	if discovery.RegistryMode != "signed-ocg-registry-error" || discovery.RegistryError == nil {
		t.Fatalf("bad signature discovery = %#v", discovery)
	}

	registryDir = t.TempDir()
	writeTestJWKS(t, registryDir)
	malformed := map[string]any{"ocg_version": "0.1"}
	signManifest(malformed)
	writeJSONFile(t, filepath.Join(registryDir, "signed", "malformed.ocg.json"), malformed)
	server.registryDir = registryDir
	discovery = server.loadAcpDiscovery()
	if discovery.RegistryMode != "signed-ocg-registry-error" || !strings.Contains(fmt.Sprint(discovery.RegistryError), "app is required") {
		t.Fatalf("malformed discovery = %#v", discovery)
	}
}

func TestGoStoreSerializesFirstReadWriteAndUsesPrivatePermissions(t *testing.T) {
	server, dataDir := testServer(t)
	handler := server.Routes()
	var wg sync.WaitGroup
	errors := make(chan error, 2)
	wg.Add(2)
	go func() {
		defer wg.Done()
		status, _, err := requestJSONResult(handler, http.MethodGet, "/api/superapp-state", nil)
		if err == nil && status != http.StatusOK {
			err = fmt.Errorf("state status = %d", status)
		}
		errors <- err
	}()
	go func() {
		defer wg.Done()
		status, _, err := requestJSONResult(handler, http.MethodPost, "/api/preferences", map[string]any{"key": "race_preference", "value": "User wants race-safe stores.", "source": "go-api-test"})
		if err == nil && status != http.StatusCreated {
			err = fmt.Errorf("preference status = %d", status)
		}
		errors <- err
	}()
	wg.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile(filepath.Join(dataDir, "superapp-store.json"))
	if err != nil {
		t.Fatal(err)
	}
	var store StoreState
	if err := json.Unmarshal(raw, &store); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, event := range store.PreferenceEvents {
		if event.Key == "race_preference" {
			found = true
		}
	}
	if !found {
		t.Fatalf("race_preference missing from store: %#v", store.PreferenceEvents)
	}
	if info, err := os.Stat(dataDir); err != nil || info.Mode().Perm() != 0o700 {
		t.Fatalf("data dir permissions = %v err=%v", info.Mode().Perm(), err)
	}
	if info, err := os.Stat(filepath.Join(dataDir, "superapp-store.json")); err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("store permissions = %v err=%v", info.Mode().Perm(), err)
	}
}

func TestGoJSONBodyLimit(t *testing.T) {
	server, _ := testServer(t)
	req := httptest.NewRequest(http.MethodPost, "/api/preferences", strings.NewReader(`{"key":"big","value":"`+strings.Repeat("x", requestBodyLimitBytes)+`"}`))
	req.Header.Set("content-type", "application/json")
	rec := httptest.NewRecorder()
	server.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversized status = %d body=%s", rec.Code, rec.Body.String())
	}
}

func writeTestJWKS(t *testing.T, registryDir string) {
	t.Helper()
	writeJSONFile(t, filepath.Join(registryDir, "jwks", "test-registry-jwks.json"), map[string]any{
		"issuer": "https://registry.meshkit.ai",
		"keys": []any{map[string]any{
			"kid": "ocg-registry-test-2026-05", "alg": "HS256-test-only", "kty": "oct",
			"k": base64.RawURLEncoding.EncodeToString([]byte("meshkit-test-registry-signing-key-not-production")), "status": "active",
		}},
	})
}

func writeJSONFile(t *testing.T, path string, value any) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	raw, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, raw, 0o600); err != nil {
		t.Fatal(err)
	}
}

func validManifestWithSignature(signature string) map[string]any {
	return map[string]any{
		"ocg_version": "0.1",
		"app": map[string]any{
			"app_id": "ai.meshkit.sample.notes", "display_name": "Mint Notes", "platform": "android",
			"package_name": "ai.meshkit.sample.notes", "publisher": "MeshKit Samples", "verified": true,
		},
		"capabilities": []any{map[string]any{
			"id": "notes.append_note", "version": "1.0", "description": "Append note.", "risk": "write:user_content", "consent": "per_invocation",
			"input_schema": map[string]any{"type": "object"}, "result_schema": map[string]any{"type": "object"},
		}},
		"registry_signature": map[string]any{
			"alg": "HS256-test-only", "kid": "ocg-registry-test-2026-05", "canonicalization": "ocg-canonical-json/v1",
			"issued_at": "2026-05-17T00:00:00Z", "value": signature,
		},
	}
}

func signManifest(manifest map[string]any) {
	unsigned := map[string]any{}
	for key, value := range manifest {
		if key != "registry_signature" {
			unsigned[key] = value
		}
	}
	mac := hmac.New(sha256.New, []byte("meshkit-test-registry-signing-key-not-production"))
	mac.Write([]byte(canonicalJSON(unsigned)))
	manifest["registry_signature"] = map[string]any{
		"alg": "HS256-test-only", "kid": "ocg-registry-test-2026-05", "canonicalization": "ocg-canonical-json/v1",
		"issued_at": "2026-05-17T00:00:00Z", "value": base64.RawURLEncoding.EncodeToString(mac.Sum(nil)),
	}
}
