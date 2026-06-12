import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  RefreshControl,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View
} from "react-native";
import {
  executeDailyMartOnchain,
  executeMintNotesOffchain,
  fetchSuperappState,
  savePreference,
  sendAgentChat,
  summarizeSuperappState
} from "./src/api";
import { configureApiPlatform } from "./src/config";

const paymentPreference =
  "agent payments use on-chain OKRW proof and non-payment calls stay off-chain";

function formatAmount(value) {
  return Number(value || 0).toFixed(2);
}

function Pill({ children, tone = "neutral" }) {
  return <Text style={[styles.pill, styles[`pill_${tone}`]]}>{children}</Text>;
}

function Section({ title, meta, children, testID }) {
  return (
    <View style={styles.section} testID={testID}>
      <View style={styles.sectionHeader}>
        <Text style={styles.sectionTitle}>{title}</Text>
        {meta ? <Text style={styles.sectionMeta}>{meta}</Text> : null}
      </View>
      {children}
    </View>
  );
}

function Row({ title, subtitle, right, route, accent }) {
  return (
    <View
      accessibilityLabel={[title, subtitle, right].filter(Boolean).join(", ")}
      style={[styles.row, route ? styles[`row_${route}`] : null, accent ? styles[`row_${accent}`] : null]}
    >
      <View style={styles.rowBody}>
        <Text numberOfLines={1} ellipsizeMode="middle" style={styles.rowTitle}>{title}</Text>
        <Text numberOfLines={2} ellipsizeMode="tail" style={styles.rowSubtitle}>{subtitle}</Text>
      </View>
      {right ? <Text numberOfLines={1} ellipsizeMode="tail" style={styles.rowRight}>{right}</Text> : null}
    </View>
  );
}

function Metric({ value, label }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

function EmptyState({ label }) {
  return <Text style={styles.emptyState}>{label}</Text>;
}

function StatusBanner({ message, tone = "info", onRetry }) {
  if (!message) return null;
  return (
    <View accessibilityLiveRegion="polite" style={[styles.statusBanner, styles[`statusBanner_${tone}`]]}>
      <Text style={styles.statusText}>{message}</Text>
      {onRetry ? (
        <Pressable accessibilityRole="button" accessibilityLabel="Retry loading superapp state" hitSlop={8} onPress={onRetry} style={styles.inlineButton}>
          <Text style={styles.inlineButtonText}>Retry</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

function ActionButton({ children, kind = "primary", disabled, onPress, accessibilityLabel }) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled: Boolean(disabled), busy: Boolean(disabled) }}
      disabled={disabled}
      hitSlop={6}
      onPress={onPress}
      style={({ pressed }) => [
        styles[`${kind}Button`],
        pressed && !disabled ? styles.buttonPressed : null,
        disabled ? styles.buttonDisabled : null
      ]}
    >
      <Text style={styles[`${kind}ButtonText`]}>{children}</Text>
    </Pressable>
  );
}

export default function App() {
  const [state, setState] = useState(null);
  const [preferenceKey, setPreferenceKey] = useState("payment_proof_policy");
  const [preferenceValue, setPreferenceValue] = useState(paymentPreference);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [actionStatus, setActionStatus] = useState("Ready");
  const [actionInFlight, setActionInFlight] = useState(null);
  const [errorMessage, setErrorMessage] = useState("");
  const [chatInput, setChatInput] = useState("What can you do? Remember low-sugar groceries, append a note saying \"buy bananas first\", and buy DailyMart essentials for 42 OKRW.");
  const [chatMessages, setChatMessages] = useState([]);
  const actionLockRef = useRef(null);

  const summary = useMemo(() => state ? summarizeSuperappState(state) : null, [state]);

  const load = useCallback(async ({ silent = false } = {}) => {
    if (!silent) setLoading(true);
    try {
      setState(await fetchSuperappState());
      setErrorMessage("");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setErrorMessage(message);
      if (!silent) {
        Alert.alert("MeshKit API unavailable", message);
      }
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    configureApiPlatform(Platform.OS);
    void load();
  }, [load]);

  const persistPreference = useCallback(async () => {
    if (actionLockRef.current) {
      return;
    }
    if (!preferenceKey.trim() || !preferenceValue.trim()) {
      setActionStatus("Preference key and value are required.");
      return;
    }
    actionLockRef.current = "save";
    setActionInFlight("save");
    setActionStatus("Saving preference...");
    try {
      const payload = await savePreference({ key: preferenceKey.trim(), value: preferenceValue.trim() });
      setState(payload.state);
      setErrorMessage("");
      setActionStatus(payload.droppedPreference ? `Filtered ${preferenceKey}` : `Saved ${preferenceKey}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setErrorMessage(message);
      setActionStatus(message);
    } finally {
      actionLockRef.current = null;
      setActionInFlight(null);
    }
  }, [preferenceKey, preferenceValue]);

  const execute = useCallback(async (kind) => {
    if (actionLockRef.current) {
      return;
    }
    actionLockRef.current = kind;
    setActionInFlight(kind);
    setActionStatus("Executing app-to-app MCP...");
    try {
      const payload = kind === "paid"
        ? await executeDailyMartOnchain()
        : await executeMintNotesOffchain();
      setErrorMessage("");
      await load({ silent: true });
      setActionStatus(`${payload.routeDecision.route} ${payload.transactionRecord.status}: ${payload.transactionRecord.requestId}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setErrorMessage(message);
      setActionStatus(message);
    } finally {
      actionLockRef.current = null;
      setActionInFlight(null);
    }
  }, [load]);

  const sendChat = useCallback(async () => {
    const content = chatInput.trim();
    if (actionLockRef.current || !content) {
      return;
    }
    const userMessage = { role: "user", content };
    const nextMessages = [...chatMessages, userMessage].filter((message) => message.role === "user" || message.role === "assistant");
    actionLockRef.current = "chat";
    setActionInFlight("chat");
    setActionStatus("Talking to MeshKit agent...");
    setChatMessages(nextMessages);
    setChatInput("");
    try {
      const payload = await sendAgentChat({ messages: nextMessages });
      if (payload.state) {
        setState(payload.state);
      } else {
        await load({ silent: true });
      }
      setErrorMessage("");
      setChatMessages([...nextMessages, payload.assistant]);
      setActionStatus(`Agent replied with ${payload.toolResults?.length || 0} ACP tool results.`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setErrorMessage(message);
      setActionStatus(message);
      setChatMessages([...nextMessages, { role: "assistant", content: message }]);
    } finally {
      actionLockRef.current = null;
      setActionInFlight(null);
    }
  }, [chatInput, chatMessages, load]);

  if (loading && !state) {
    return (
      <SafeAreaView style={styles.loadingScreen}>
        <ActivityIndicator />
        <Text style={styles.loadingText}>Loading MeshKit superapp</Text>
      </SafeAreaView>
    );
  }

  const apps = state?.apps || [];
  const promotedMemory = state?.memory?.promotedMemory || [];
  const routes = state?.routing || [];
  const executions = state?.executionRecords || [];
  const ledger = state?.settlementLedger || { entries: [], summary: {} };

  const actionDisabled = Boolean(actionInFlight);

  return (
    <SafeAreaView style={styles.screen}>
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : undefined}
        style={styles.keyboardRoot}
      >
      <ScrollView
        contentContainerStyle={styles.content}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => {
          setRefreshing(true);
          void load({ silent: true });
        }} />}
      >
        <View style={styles.header}>
          <View>
            <Text style={styles.eyebrow}>MeshKit ACP</Text>
            <Text style={styles.title}>Superapp</Text>
          </View>
          <View style={styles.summaryBox}>
            <Text style={styles.summaryValue}>{formatAmount(summary?.totalConfirmed)}</Text>
            <Text style={styles.summaryLabel}>{summary?.asset || "OKRW"} settled</Text>
          </View>
        </View>

        <StatusBanner message={errorMessage} tone="error" onRetry={() => void load()} />
        <StatusBanner message={actionStatus} tone={errorMessage ? "warning" : "info"} />

        <View style={styles.metrics}>
          <Metric value={summary?.appCount || 0} label="Apps" />
          <Metric value={summary?.promotedMemoryCount || 0} label="Memories" />
          <Metric value={summary?.executionCount || 0} label="Executions" />
          <Metric value={summary?.settlementCount || 0} label="Ledger" />
        </View>

        <Section title="Agent Chat" meta={actionInFlight === "chat" ? "talking" : "live"} testID="agent-chat-section">
          <View style={styles.chatLog}>
            {chatMessages.length === 0 ? <EmptyState label="Start a real conversation with the MeshKit agent." /> : null}
            {chatMessages.slice(-6).map((message, index) => (
              <View
                key={`${message.role}-${index}-${message.content}`}
                style={[styles.chatBubble, message.role === "user" ? styles.chatBubble_user : styles.chatBubble_assistant]}
              >
                <Text style={styles.chatRole}>{message.role === "user" ? "You" : "Agent"}</Text>
                <Text style={styles.chatText}>{message.content}</Text>
              </View>
            ))}
          </View>
          <View style={styles.inputGroup}>
            <TextInput
              accessibilityLabel="Agent chat message"
              multiline
              style={[styles.input, styles.chatInput]}
              value={chatInput}
              onChangeText={setChatInput}
              placeholder="Ask the MeshKit agent to remember, route, execute, or settle..."
            />
            <ActionButton
              accessibilityLabel="Send agent chat message"
              disabled={actionDisabled || !chatInput.trim()}
              onPress={sendChat}
            >
              {actionInFlight === "chat" ? "Talking..." : "Send Chat"}
            </ActionButton>
          </View>
        </Section>

        <Section title="Discovery" meta={state?.acpDiscovery?.registryMode || "registry"} testID="discovery-section">
          {apps.length === 0 ? <EmptyState label="No ACP apps discovered." /> : null}
          {apps.map((app) => (
            <Row
              key={app.appId}
              title={app.displayName}
              subtitle={`${app.acpEndpoint} · ${app.mcpTransport}`}
              right={app.capabilities?.[0]?.routingHint}
            />
          ))}
        </Section>

        <Section title="Memory" meta="brain" testID="memory-section">
          <View style={styles.inputGroup}>
            <TextInput
              accessibilityLabel="Preference key"
              autoCapitalize="none"
              style={styles.input}
              value={preferenceKey}
              onChangeText={setPreferenceKey}
              placeholder="preference key"
            />
            <TextInput
              accessibilityLabel="Preference value"
              multiline
              style={[styles.input, styles.textArea]}
              value={preferenceValue}
              onChangeText={setPreferenceValue}
              placeholder="preference value"
            />
            <ActionButton
              accessibilityLabel="Save preference memory"
              disabled={actionDisabled}
              onPress={persistPreference}
            >
              {actionInFlight === "save" ? "Saving..." : "Save Preference"}
            </ActionButton>
          </View>
          {promotedMemory.length === 0 ? <EmptyState label="No promoted preference memory yet." /> : null}
          {promotedMemory.slice(0, 4).map((memory) => (
            <Row
              key={memory.memoryId}
              title={memory.key}
              subtitle={memory.content}
              right={String(memory.importance)}
            />
          ))}
        </Section>

        <Section title="Route / Execution" meta={actionInFlight ? "running" : "ready"} testID="execution-section">
          <View style={styles.actionRow}>
            <ActionButton
              kind="secondary"
              accessibilityLabel="Execute MintNotes off-chain"
              disabled={actionDisabled}
              onPress={() => execute("unpaid")}
            >
              {actionInFlight === "unpaid" ? "Submitting..." : "MintNotes Off-chain"}
            </ActionButton>
            <ActionButton
              accessibilityLabel="Execute DailyMart 42 OKRW on-chain"
              disabled={actionDisabled}
              onPress={() => execute("paid")}
            >
              {actionInFlight === "paid" ? "Confirming..." : "DailyMart 42 OKRW"}
            </ActionButton>
          </View>
          {routes.length === 0 ? <EmptyState label="No route decisions available." /> : null}
          {routes.map((route) => (
            <Row
              key={route.capabilityId}
              title={route.capabilityId}
              subtitle={`${route.appliedPolicy?.paymentProof} · ${route.appliedPolicy?.payloadPrivacy}`}
              right={route.route}
              route={route.route}
            />
          ))}
          {executions.length === 0 ? <EmptyState label="No executions submitted." /> : null}
          {executions.slice(-3).reverse().map((record) => (
            <Row
              key={record.requestId}
              title={record.requestId}
              subtitle={`${record.capabilityId} · ${record.recordType}`}
              right={record.txHash ? "tx" : "off-chain"}
              route={record.route}
            />
          ))}
        </Section>

        <Section title="Ledger" meta={`${formatAmount(ledger.summary?.totalDebits)} debits`} testID="ledger-section">
          {ledger.entries.length === 0 ? <EmptyState label="No on-chain settlement records." /> : null}
          {ledger.entries.map((entry) => (
            <Row
              key={entry.entryId}
              title={`${entry.counterparty} · ${entry.category}`}
              subtitle={`${entry.requestId} · ${entry.status} · ${entry.paymentProof}`}
              right={`${formatAmount(entry.amount)} ${entry.asset}`}
              route="onchain"
            />
          ))}
          <View style={styles.ledgerFooter}>
            <Pill tone="debit">Debits {formatAmount(ledger.summary?.totalDebits)}</Pill>
            <Pill tone="credit">Credits {formatAmount(ledger.summary?.totalCredits)}</Pill>
          </View>
        </Section>
      </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  screen: { flex: 1, backgroundColor: "#eef2f5" },
  keyboardRoot: { flex: 1 },
  loadingScreen: { flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: "#eef2f5" },
  loadingText: { marginTop: 12, color: "#26313d" },
  content: { padding: 16, gap: 14 },
  header: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", marginBottom: 4 },
  eyebrow: { color: "#4c6475", fontSize: 12, fontWeight: "700", textTransform: "uppercase" },
  title: { color: "#111820", fontSize: 32, fontWeight: "800" },
  summaryBox: { minWidth: 118, padding: 12, borderRadius: 8, backgroundColor: "#172638" },
  summaryValue: { color: "#ffffff", fontSize: 22, fontWeight: "800", textAlign: "right" },
  summaryLabel: { color: "#b9d7e8", fontSize: 12, textAlign: "right" },
  metrics: { flexDirection: "row", flexWrap: "wrap", justifyContent: "space-between", gap: 8, padding: 12, borderRadius: 8, backgroundColor: "#ffffff", borderWidth: 1, borderColor: "#d7e0e7" },
  metric: { width: "48%", minHeight: 48 },
  metricValue: { color: "#111820", fontSize: 20, fontWeight: "800" },
  metricLabel: { color: "#5f6d78", fontSize: 11 },
  section: { gap: 10, padding: 12, borderRadius: 8, backgroundColor: "#ffffff", borderWidth: 1, borderColor: "#d7e0e7" },
  sectionHeader: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 },
  sectionTitle: { color: "#111820", fontSize: 18, fontWeight: "800" },
  sectionMeta: { color: "#5f6d78", fontSize: 12, flexShrink: 1, textAlign: "right" },
  row: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 10, borderRadius: 7, backgroundColor: "#f8fafb", borderWidth: 1, borderColor: "#e2e8ee" },
  row_onchain: { borderLeftWidth: 4, borderLeftColor: "#0f6c81" },
  row_offchain: { borderLeftWidth: 4, borderLeftColor: "#b45c3c" },
  rowBody: { flex: 1, flexShrink: 1, gap: 3, minWidth: 0 },
  rowTitle: { color: "#18222c", fontSize: 14, fontWeight: "700" },
  rowSubtitle: { color: "#65717c", fontSize: 12 },
  rowRight: { color: "#26313d", fontSize: 12, fontWeight: "700", textAlign: "right", maxWidth: 116, flexShrink: 1 },
  chatLog: { gap: 8 },
  chatBubble: { gap: 4, padding: 10, borderRadius: 7, borderWidth: 1 },
  chatBubble_user: { backgroundColor: "#eef8fb", borderColor: "#bad7e2" },
  chatBubble_assistant: { backgroundColor: "#f8fafb", borderColor: "#d8e1e8" },
  chatRole: { color: "#52616f", fontSize: 11, fontWeight: "800", textTransform: "uppercase" },
  chatText: { color: "#18222c", fontSize: 13, lineHeight: 18 },
  inputGroup: { gap: 8 },
  input: { minHeight: 44, borderRadius: 7, borderWidth: 1, borderColor: "#cbd6df", paddingHorizontal: 10, color: "#111820", backgroundColor: "#fbfdff" },
  textArea: { minHeight: 76, paddingTop: 10, textAlignVertical: "top" },
  chatInput: { minHeight: 72, paddingTop: 10, textAlignVertical: "top" },
  actionRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  primaryButton: { minHeight: 44, alignItems: "center", justifyContent: "center", paddingHorizontal: 12, borderRadius: 7, backgroundColor: "#0f6c81", flexGrow: 1, flexBasis: 148 },
  primaryButtonText: { color: "#ffffff", fontSize: 13, fontWeight: "800" },
  secondaryButton: { minHeight: 44, alignItems: "center", justifyContent: "center", paddingHorizontal: 12, borderRadius: 7, backgroundColor: "#fff1eb", flexGrow: 1, flexBasis: 148, borderWidth: 1, borderColor: "#efc2ae" },
  secondaryButtonText: { color: "#7a351e", fontSize: 13, fontWeight: "800" },
  buttonPressed: { opacity: 0.82 },
  buttonDisabled: { opacity: 0.48 },
  statusBanner: { flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 10, padding: 10, borderRadius: 8, borderWidth: 1 },
  statusBanner_info: { backgroundColor: "#f4f8fb", borderColor: "#cddde8" },
  statusBanner_warning: { backgroundColor: "#fff8ec", borderColor: "#efd29d" },
  statusBanner_error: { backgroundColor: "#fff0f0", borderColor: "#efb6b6" },
  statusText: { color: "#26313d", fontSize: 12, fontWeight: "700", flex: 1 },
  inlineButton: { minHeight: 44, justifyContent: "center", paddingHorizontal: 12, borderRadius: 7, backgroundColor: "#172638" },
  inlineButtonText: { color: "#ffffff", fontSize: 12, fontWeight: "800" },
  emptyState: { color: "#52616f", fontSize: 12, paddingVertical: 8 },
  ledgerFooter: { flexDirection: "row", gap: 8, flexWrap: "wrap" },
  pill: { overflow: "hidden", borderRadius: 7, paddingHorizontal: 10, paddingVertical: 6, fontSize: 12, fontWeight: "800" },
  pill_neutral: { backgroundColor: "#eef4f7", color: "#26313d" },
  pill_debit: { backgroundColor: "#e5f4f7", color: "#0b5364" },
  pill_credit: { backgroundColor: "#fff0e8", color: "#7a351e" }
});
