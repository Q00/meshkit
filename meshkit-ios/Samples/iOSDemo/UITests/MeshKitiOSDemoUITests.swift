import XCTest

final class MeshKitiOSDemoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIApplication(bundleIdentifier: "ai.meshkit.sample.hermeschat").terminate()
        XCUIApplication(bundleIdentifier: "ai.meshkit.sample.mintnotes").terminate()
        XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart").terminate()
        // URL-scheme confirmation alerts are handled explicitly after the tap so XCTest
        // does not retry the original app button after SpringBoard already foregrounded
        // the target app.
    }

    func testHermesChatToMintNotesToCallback() throws {
        let hermes = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.hermeschat")
        configureHermesDemoSigning(hermes)
        hermes.launch()
        XCTAssertTrue(hermes.staticTexts["Hermes Chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(hermes.staticTexts["MeshKit — make apps callable"].exists)

        let openButton = hermes.buttons["Open Mint Notes via notes.append_note"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8))
        openButton.tap()
        tapSystemOpenIfPresent()

        let mint = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.mintnotes")
        configureTargetRequestTrust(mint)
        XCTAssertTrue(mint.staticTexts["Mint Notes"].waitForExistence(timeout: 8))
        XCTAssertTrue(mint.staticTexts["Target app • notes.append_note"].exists)
        XCTAssertTrue(mint.staticTexts["Received MeshKit request"].exists)

        let approveButton = mint.buttons["Approve & Save, then callback Hermes"]
        XCTAssertTrue(approveButton.waitForExistence(timeout: 8))
        approveButton.tap()
        tapSystemOpenIfPresent()
        hermes.activate()

        XCTAssertTrue(hermes.staticTexts["Hermes Chat"].waitForExistence(timeout: 8))
        let callback = hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Callback received from target app")).firstMatch
        XCTAssertTrue(callback.waitForExistence(timeout: 8))
    }

    func testHermesChatToDailyMartPurchaseAndTargetProof() throws {
        runDailyMartPurchaseFlow(pressHomeDuringBackgroundCheckout: false)
    }

    func testDailyMartPurchaseCompletesWhileHermesIsHomeScreenBackgrounded() throws {
        runDailyMartPurchaseFlow(pressHomeDuringBackgroundCheckout: true)
    }

    func testDailyMartSecondPurchaseUsesSavedConsentBackgroundMCPCall() throws {
        runDailyMartProductionSimulatorVideoFlow()
    }

    func testDailyMartConfirmedReceiptRendersProviderNeutralChainProofFields() throws {
        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        dailyMart.launchArguments = ["--confirmed-receipt-ui-proof"]
        dailyMart.launch()

        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts["Order placed"].waitForExistence(timeout: 8))
        assertVisibleText("Confirmed provider-neutral chain proof", in: dailyMart)
        assertVisibleElement("confirmed-chain-proof-debug-ui", in: dailyMart)

        let providerNeutralConfirmedFields = [
            ("provider", "Provider"),
            ("chainId", "Chain ID"),
            ("network", "Network"),
            ("proofType", "Proof type"),
            ("status", "Status"),
            ("presentationState", "Presentation"),
            ("requestHash", "Request hash"),
            ("requestNonce", "Request nonce"),
            ("policyId", "Policy ID"),
            ("policyHash", "Policy hash"),
            ("walletAddress", "Wallet"),
            ("amount", "Amount"),
            ("asset", "Asset"),
            ("recipient", "Recipient"),
            ("anchoringReference", "Anchor"),
            ("txHash", "Tx hash"),
            ("explorerUrl", "Explorer"),
            ("confirmedAt", "Confirmed at"),
            ("providerExtensions", "Provider extensions")
        ]

        for (_, label) in providerNeutralConfirmedFields {
            assertVisibleText(label, in: dailyMart)
        }

        for (schemaName, _) in providerNeutralConfirmedFields {
            assertVisibleElement("chain-proof-field-\(schemaName)", in: dailyMart)
        }

        for value in [
            "maroo",
            "maroo-testnet-1",
            "maroo-testnet",
            "payment_execution",
            "confirmed",
            "paid_complete",
            "ios-grocery-confirmed-ui-nonce",
            "policy-hermes-dailymart-okrw-v1",
            "maroo1dailyMartAgentWallet",
            "100",
            "OKRW",
            "request-anchor-sha256-",
            "0xokrwDailyMartConfirmedUIReceipt",
            "https://explorer-testnet.maroo.io/tx/0xokrwDailyMartConfirmedUIReceipt",
            "2026-05-31T12:00:00Z",
            "none"
        ] {
            assertVisibleText(value, in: dailyMart)
        }
    }

    func testDailyMartPendingReceiptRendersProviderNeutralChainProofFields() throws {
        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        dailyMart.launchArguments = ["--pending-receipt-ui-proof"]
        dailyMart.launch()

        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        assertVisibleText("Pending provider-neutral chain proof", in: dailyMart)
        assertVisibleElement("pending-chain-proof-debug-ui", in: dailyMart)

        let providerNeutralPendingFields = [
            ("provider", "Provider"),
            ("chainId", "Chain ID"),
            ("network", "Network"),
            ("proofType", "Proof type"),
            ("status", "Status"),
            ("presentationState", "Presentation"),
            ("requestHash", "Request hash"),
            ("requestNonce", "Request nonce"),
            ("policyId", "Policy ID"),
            ("policyHash", "Policy hash"),
            ("walletAddress", "Wallet"),
            ("amount", "Amount"),
            ("asset", "Asset"),
            ("recipient", "Recipient"),
            ("anchoringReference", "Anchor"),
            ("executionAttemptId", "Execution attempt"),
            ("paymentId", "Payment ID"),
            ("authorizationId", "Authorization ID"),
            ("executionId", "Execution ID"),
            ("executionKind", "Execution kind"),
            ("anchorTxHash", "Anchor tx hash"),
            ("submittedAt", "Submitted at"),
            ("externalChainExitCondition", "External chain"),
            ("externalChainBlockerType", "Blocker type"),
            ("externalChainOperation", "Operation"),
            ("externalChainEndpoint", "Endpoint"),
            ("externalChainMessage", "Message")
        ]

        for (_, label) in providerNeutralPendingFields {
            assertVisibleText(label, in: dailyMart)
        }

        for (schemaName, _) in providerNeutralPendingFields {
            assertVisibleElement("chain-proof-field-\(schemaName)", in: dailyMart)
        }

        for value in [
            "maroo",
            "maroo-testnet-1",
            "maroo-testnet",
            "payment_execution",
            "pending",
            "submitted_not_final",
            "ios-grocery-pending-ui-nonce",
            "policy-hermes-dailymart-okrw-v1",
            "maroo1dailyMartAgentWallet",
            "100",
            "OKRW",
            "request-anchor-sha256-",
            "meshkit-execution-attempt/v1:pay-pending-ui:auth-pending-ui:exec-pending-ui",
            "pay-pending-ui",
            "auth-pending-ui",
            "exec-pending-ui",
            "payment",
            "0xanchorDailyMartPendingUIReceipt",
            "2026-05-31T12:05:00Z",
            "BlockedByExternalChain",
            "payment_confirmation_unavailable",
            "executeOKRWTransfer",
            "https://rpc-testnet.maroo.io",
            "maroo live OKRW confirmation is unavailable for this demo run"
        ] {
            assertVisibleText(value, in: dailyMart)
        }

        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Tx hash")).firstMatch.exists,
            "Pending receipt UI must not render a payment txHash field as proof of completion"
        )
        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order placed")).firstMatch.exists,
            "Pending receipt UI must not present the order as paid or complete"
        )
    }

    func testDailyMartFailedReceiptRendersProviderNeutralChainProofFields() throws {
        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        dailyMart.launchArguments = ["--failed-receipt-ui-proof"]
        dailyMart.launch()

        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        assertVisibleText("Failed provider-neutral chain proof", in: dailyMart)
        assertVisibleElement("failed-chain-proof-debug-ui", in: dailyMart)

        let providerNeutralFailedFields = [
            ("provider", "Provider"),
            ("chainId", "Chain ID"),
            ("network", "Network"),
            ("proofType", "Proof type"),
            ("status", "Status"),
            ("presentationState", "Presentation"),
            ("requestHash", "Request hash"),
            ("requestNonce", "Request nonce"),
            ("policyId", "Policy ID"),
            ("policyHash", "Policy hash"),
            ("walletAddress", "Wallet"),
            ("amount", "Amount"),
            ("asset", "Asset"),
            ("recipient", "Recipient"),
            ("anchoringReference", "Anchor"),
            ("executionAttemptId", "Execution attempt"),
            ("paymentId", "Payment ID"),
            ("authorizationId", "Authorization ID"),
            ("executionId", "Execution ID"),
            ("executionKind", "Execution kind"),
            ("anchorTxHash", "Anchor tx hash"),
            ("errorCode", "Error code"),
            ("errorMessage", "Error message"),
            ("externalChainExitCondition", "External chain"),
            ("externalChainBlockerType", "Blocker type"),
            ("externalChainOperation", "Operation"),
            ("externalChainEndpoint", "Endpoint"),
            ("externalChainMessage", "Message")
        ]

        for (_, label) in providerNeutralFailedFields {
            assertVisibleText(label, in: dailyMart)
        }

        for (schemaName, _) in providerNeutralFailedFields {
            assertVisibleElement("chain-proof-field-\(schemaName)", in: dailyMart)
        }

        for value in [
            "maroo",
            "maroo-testnet-1",
            "maroo-testnet",
            "payment_execution",
            "failed",
            "attempted_failed",
            "ios-grocery-failed-ui-nonce",
            "policy-hermes-dailymart-okrw-v1",
            "maroo1dailyMartAgentWallet",
            "100",
            "OKRW",
            "request-anchor-sha256-",
            "meshkit-execution-attempt/v1:pay-failed-ui:auth-failed-ui:exec-failed-ui",
            "pay-failed-ui",
            "auth-failed-ui",
            "exec-failed-ui",
            "payment",
            "0xanchorDailyMartFailedUIReceipt",
            "payment_confirmation_unavailable",
            "maroo RPC did not return a transaction receipt",
            "BlockedByExternalChain",
            "executeOKRWTransfer",
            "https://rpc-testnet.maroo.io"
        ] {
            assertVisibleText(value, in: dailyMart)
        }

        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Tx hash")).firstMatch.exists,
            "Failed receipt UI must not render a payment txHash field as proof of completion"
        )
        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order placed")).firstMatch.exists,
            "Failed receipt UI must not present the order as paid or complete"
        )
    }

    func testDailyMartPolicyDeniedReceiptRendersProviderNeutralChainProofFields() throws {
        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        dailyMart.launchArguments = ["--policy-denied-receipt-ui-proof"]
        dailyMart.launch()

        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        assertVisibleText("Policy-denied provider-neutral chain proof", in: dailyMart)
        assertVisibleElement("policy-denied-chain-proof-debug-ui", in: dailyMart)

        let providerNeutralPolicyDeniedFields = [
            ("provider", "Provider"),
            ("chainId", "Chain ID"),
            ("network", "Network"),
            ("proofType", "Proof type"),
            ("status", "Status"),
            ("presentationState", "Presentation"),
            ("requestHash", "Request hash"),
            ("requestNonce", "Request nonce"),
            ("policyId", "Policy ID"),
            ("policyHash", "Policy hash"),
            ("walletAddress", "Wallet"),
            ("amount", "Amount"),
            ("asset", "Asset"),
            ("recipient", "Recipient"),
            ("anchoringReference", "Anchor"),
            ("executionAttemptId", "Execution attempt"),
            ("executionId", "Execution ID"),
            ("errorCode", "Error code"),
            ("errorMessage", "Error message")
        ]

        for (schemaName, _) in providerNeutralPolicyDeniedFields {
            assertVisibleElement("chain-proof-field-\(schemaName)", in: dailyMart)
        }

        for (_, label) in providerNeutralPolicyDeniedFields {
            assertVisibleText(label, in: dailyMart)
        }

        for value in [
            "maroo",
            "maroo-testnet-1",
            "maroo-testnet",
            "policy_denial",
            "failed",
            "policy_denied",
            "ios-grocery-policy-denied-ui-nonce",
            "policy-hermes-dailymart-okrw-v1",
            "maroo1dailyMartAgentWallet",
            "250",
            "OKRW",
            "request-anchor-sha256-",
            "meshkit-execution-attempt/v1:policy-denied-ui:wallet-policy:exec-policy-denied-ui",
            "exec-policy-denied-ui",
            "wallet_policy_denied",
            "policy-single-payment-max-exceeded"
        ] {
            assertVisibleText(value, in: dailyMart)
        }

        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Tx hash")).firstMatch.exists,
            "Policy-denied receipt UI must not render a payment txHash field"
        )
        XCTAssertFalse(
            dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order placed")).firstMatch.exists,
            "Policy-denied receipt UI must not present the order as paid or complete"
        )
    }

    private func runDailyMartProductionSimulatorVideoFlow() {
        let hermes = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.hermeschat")
        configureHermesDemoSigning(hermes)
        hermes.launch()
        XCTAssertTrue(hermes.staticTexts["Hermes Chat"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 7.0) // show intent typing + OCG analysis before target app receives the request

        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        configureDailyMartReceiptSigning(dailyMart)
        dailyMart.launchArguments = ["--demo-received-request"]
        dailyMart.launch()
        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts["Review consent request"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2.0)
        let approveButton = dailyMart.buttons["Grant one-time DailyMart consent"]
        XCTAssertTrue(approveButton.waitForExistence(timeout: 8))
        approveButton.tap()
        confirmDailyMartConsentModal(dailyMart)
        XCTAssertTrue(dailyMart.staticTexts["Consent granted"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts["Order intent pending"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2.0)

        hermes.terminate()
        hermes.launchArguments = ["--demo-first-order-complete"]
        configureHermesDemoSigning(hermes)
        hermes.launch()
        XCTAssertTrue(hermes.staticTexts["Hermes Chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order DM-2026-0509-001")).firstMatch.waitForExistence(timeout: 8))
        let savedConsentButton = hermes.buttons["Call DailyMart again with saved consent"]
        if !savedConsentButton.waitForExistence(timeout: 2) { hermes.swipeUp() }
        XCTAssertTrue(savedConsentButton.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.0)
        savedConsentButton.tap()
        let foregroundProofAlert = hermes.alerts["Foreground proof: DailyMart stays background"]
        XCTAssertTrue(foregroundProofAlert.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 2.0)
        foregroundProofAlert.buttons["Run background MCP call"].tap()
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "DailyMart saved-consent MCP call running")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(dailyMart.state, .runningForeground, "Second call must not foreground DailyMart approval UI")
        Thread.sleep(forTimeInterval: 6.0)
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Still waiting for DailyMart target-signed receipt")).firstMatch.waitForExistence(timeout: 8))

        dailyMart.terminate()
        configureDailyMartReceiptSigning(dailyMart)
        dailyMart.launchArguments = ["--saved-consent-order-proof"]
        dailyMart.launch()
        tapSystemOpenIfPresent()
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order DM-2026-0509-002")).firstMatch.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2.0)

        dailyMart.terminate()
        configureDailyMartReceiptSigning(dailyMart)
        dailyMart.launchArguments = ["--saved-consent-order-proof"]
        dailyMart.launch()
        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts["Order placed"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order DM-2026-0509-002 confirmed")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "saved-consent background MCP")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "approval_screen=false")).firstMatch.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 12.0)
    }

    private func runDailyMartPurchaseFlow(pressHomeDuringBackgroundCheckout: Bool, performSavedConsentSecondCall: Bool = false) {
        let dailyMart = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.dailymart")
        configureDailyMartReceiptSigning(dailyMart)
        configureTargetRequestTrust(dailyMart)
        dailyMart.launch()
        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        dailyMart.terminate()

        let hermes = XCUIApplication(bundleIdentifier: "ai.meshkit.sample.hermeschat")
        configureHermesDemoSigning(hermes)
        hermes.launch()
        XCTAssertTrue(hermes.staticTexts["Hermes Chat"].waitForExistence(timeout: 8))

        let buyButton = hermes.buttons["Buy Essentials with DailyMart"]
        XCTAssertTrue(buyButton.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2.0) // keep callable apps visible in the recording before selection
        buyButton.tap()
        tapSystemOpenIfPresent()

        XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
        XCTAssertTrue(dailyMart.staticTexts["Target app • grocery.purchase_essentials"].exists)
        XCTAssertTrue(dailyMart.staticTexts["Review consent request"].exists)
        Thread.sleep(forTimeInterval: 2.0)

        let approveButton = dailyMart.buttons["Grant one-time DailyMart consent"]
        XCTAssertTrue(approveButton.waitForExistence(timeout: 8))
        approveButton.tap()
        confirmDailyMartConsentModal(dailyMart)
        tapSystemOpenIfPresent()
        hermes.activate()

        XCTAssertTrue(hermes.staticTexts["Hermes Hub"].waitForExistence(timeout: 8))
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "DailyMart OKRW execution submitted")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Target-signed receipt accepted")).firstMatch.waitForExistence(timeout: 8))

        if pressHomeDuringBackgroundCheckout {
            XCUIDevice.shared.press(.home)
            Thread.sleep(forTimeInterval: 8.0)
            hermes.activate()
        } else {
            Thread.sleep(forTimeInterval: 6.0)
        }

        let callback = hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "grocery.purchase_essentials")).firstMatch
        XCTAssertTrue(callback.waitForExistence(timeout: pressHomeDuringBackgroundCheckout ? 2 : 8))
        XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "DailyMart OKRW execution submitted")).firstMatch.waitForExistence(timeout: pressHomeDuringBackgroundCheckout ? 2 : 8))

        if performSavedConsentSecondCall {
            let savedConsentButton = hermes.buttons["Call DailyMart again with saved consent"]
            if !savedConsentButton.waitForExistence(timeout: 2) {
                hermes.swipeUp()
            }
            XCTAssertTrue(savedConsentButton.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 2.0) // show first approval result + saved-consent CTA before second call
            savedConsentButton.tap()

            let foregroundProofAlert = hermes.alerts["Foreground proof: DailyMart stays background"]
            XCTAssertTrue(foregroundProofAlert.waitForExistence(timeout: 5))
            XCTAssertTrue(foregroundProofAlert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hermes Chat is foreground now")).firstMatch.waitForExistence(timeout: 2))
            XCTAssertTrue(foregroundProofAlert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "will NOT open the DailyMart approval screen")).firstMatch.waitForExistence(timeout: 2))
            Thread.sleep(forTimeInterval: 2.0) // keep foreground proof alert visible in the recording
            foregroundProofAlert.buttons["Run background MCP call"].tap()

            XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "DailyMart saved-consent MCP call running")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "No DailyMart foreground approval screen")).firstMatch.waitForExistence(timeout: 5))
            XCTAssertNotEqual(dailyMart.state, .runningForeground, "Second call must not foreground DailyMart approval UI")

            Thread.sleep(forTimeInterval: 6.0)
            XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Still waiting for DailyMart target-signed receipt")).firstMatch.waitForExistence(timeout: 8))
            XCTAssertNotEqual(dailyMart.state, .runningForeground, "DailyMart should stay off-screen while Hermes is waiting for the target receipt")
            dailyMart.terminate()
            configureDailyMartReceiptSigning(dailyMart)
            dailyMart.launchArguments = ["--saved-consent-order-proof"]
            dailyMart.launch()
            tapSystemOpenIfPresent()
            XCTAssertTrue(hermes.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order DM-2026-0509-002")).firstMatch.waitForExistence(timeout: 8))

            let openPaidReceiptButton = hermes.buttons["Open DailyMart paid receipt"]
            if !openPaidReceiptButton.waitForExistence(timeout: 2) {
                hermes.swipeUp()
            }
            XCTAssertTrue(openPaidReceiptButton.waitForExistence(timeout: 5))
            Thread.sleep(forTimeInterval: 2.0) // show Hermes receipt + explicit DailyMart proof CTA
            openPaidReceiptButton.tap()
            dailyMart.terminate()
            configureDailyMartReceiptSigning(dailyMart)
            dailyMart.launchArguments = ["--saved-consent-order-proof"]
            dailyMart.launch()

            XCTAssertTrue(dailyMart.staticTexts["DailyMart"].waitForExistence(timeout: 8))
            XCTAssertTrue(dailyMart.staticTexts["Order placed"].waitForExistence(timeout: 8))
            XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order DM-2026-0509-002 confirmed")).firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "saved-consent background MCP")).firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(dailyMart.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "approval_screen=false")).firstMatch.waitForExistence(timeout: 8))
            Thread.sleep(forTimeInterval: 18.0) // hold final DailyMart paid-order proof instead of ending on Home
        }

        if !performSavedConsentSecondCall {
            Thread.sleep(forTimeInterval: 6.0)
        }
    }

    private func configureHermesDemoSigning(_ app: XCUIApplication) {
        if let rawKey = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64"], !rawKey.isEmpty {
            app.launchEnvironment["MESHKIT_IOS_DEMO_PRIVATE_KEY_BASE64"] = rawKey
        }
        if let publicKey = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"], !publicKey.isEmpty {
            app.launchEnvironment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"] = publicKey
        }
        if let publicKey = ProcessInfo.processInfo.environment["MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64"], !publicKey.isEmpty {
            app.launchEnvironment["MESHKIT_IOS_DAILYMART_RECEIPT_PUBLIC_KEY_BASE64"] = publicKey
        }
    }

    private func configureDailyMartReceiptSigning(_ app: XCUIApplication) {
        configureTargetRequestTrust(app)
        if let privateKey = ProcessInfo.processInfo.environment["MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64"], !privateKey.isEmpty {
            app.launchEnvironment["MESHKIT_IOS_DAILYMART_RECEIPT_PRIVATE_KEY_BASE64"] = privateKey
        }
    }

    private func configureTargetRequestTrust(_ app: XCUIApplication) {
        if let publicKey = ProcessInfo.processInfo.environment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"], !publicKey.isEmpty {
            app.launchEnvironment["MESHKIT_IOS_DEMO_PUBLIC_KEY_BASE64"] = publicKey
        }
    }

    private func confirmDailyMartConsentModal(_ dailyMart: XCUIApplication) {
        let consentAlert = dailyMart.alerts["Grant DailyMart consent?"]
        XCTAssertTrue(consentAlert.waitForExistence(timeout: 5))
        XCTAssertTrue(consentAlert.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Order is not placed until the background MCP call runs")).firstMatch.waitForExistence(timeout: 2))
        Thread.sleep(forTimeInterval: 2.0) // keep DailyMart consent confirmation visible in the recording
        consentAlert.buttons["Grant one-time consent"].tap()
    }

    private func tapSystemOpenIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 2.5) {
            if alert.buttons["열기"].exists {
                alert.buttons["열기"].tap()
                return
            }
            if alert.buttons["Open"].exists {
                alert.buttons["Open"].tap()
                return
            }
            if alert.buttons.count > 1 {
                alert.buttons.element(boundBy: 1).tap()
                return
            }
        }
        let openKorean = springboard.buttons["열기"]
        if openKorean.waitForExistence(timeout: 0.8) {
            openKorean.tap()
            return
        }
        let openEnglish = springboard.buttons["Open"]
        if openEnglish.waitForExistence(timeout: 0.8) {
            openEnglish.tap()
            return
        }
    }

    private func assertVisibleText(_ text: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        for _ in 0..<6 {
            app.swipeDown()
        }
        var match = app.staticTexts.containing(predicate).firstMatch
        if match.waitForExistence(timeout: 1.0) {
            return
        }
        for _ in 0..<8 {
            app.swipeUp()
            match = app.staticTexts.containing(predicate).firstMatch
            if match.waitForExistence(timeout: 0.8) {
                return
            }
        }
        XCTFail("Expected visible text containing \(text)", file: file, line: line)
    }

    private func assertVisibleElement(_ identifier: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            app.swipeDown()
        }
        var match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if match.waitForExistence(timeout: 1.0) {
            return
        }
        for _ in 0..<8 {
            app.swipeUp()
            match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if match.waitForExistence(timeout: 0.8) {
                return
            }
        }
        XCTFail("Expected visible element with identifier \(identifier)", file: file, line: line)
    }
}
