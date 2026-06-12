import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { createSuperappState } from "../src/superapp.js";

class TestElement {
  constructor(tagName = "div", id = "") {
    this.tagName = tagName;
    this.id = id;
    this.attributes = new Map();
    this.dataset = {};
    this.style = {};
    this.children = [];
    this.listeners = new Map();
    this.value = "";
    this.hidden = false;
    this.className = "";
    this._textContent = "";
    this._innerHTML = "";
  }

  set textContent(value) {
    this._textContent = String(value);
    this._innerHTML = "";
  }

  get textContent() {
    const childrenText = this.children.map((child) => child.textContent).join("");
    return `${this._textContent}${this._innerHTML}${childrenText}`;
  }

  set innerHTML(value) {
    this._innerHTML = String(value);
    this._textContent = "";
    this.children = [];
  }

  get innerHTML() {
    return this._innerHTML;
  }

  setAttribute(name, value) {
    this.attributes.set(name, String(value));
  }

  append(child) {
    this.children.push(child);
  }

  addEventListener(eventName, handler) {
    this.listeners.set(eventName, handler);
  }

  querySelectorAll() {
    return [];
  }
}

function createHarnessDocument(html) {
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map((match) => match[1]);
  const elementsById = new Map(ids.map((id) => [id, new TestElement("div", id)]));
  elementsById.get("wallet-input").value = "0x6cf5D9C10AA00a96E55A0819A162e02c96DE3C4D";
  elementsById.get("preference-key").value = "payment_proof_policy";
  elementsById.get("preference-value").value = "agent payments use on-chain OKRW proof and non-payment calls stay off-chain";

  return {
    elementsById,
    querySelector(selector) {
      if (!selector.startsWith("#")) return null;
      return elementsById.get(selector.slice(1)) || null;
    },
    createElement(tagName) {
      return new TestElement(tagName);
    },
    createElementNS(_namespace, tagName) {
      return new TestElement(tagName);
    }
  };
}

test("first screen renders Discovery, Memory, Route/Execution, and Ledger data", async () => {
  const html = await readFile(new URL("../src/index.html", import.meta.url), "utf8");
  const documentHarness = createHarnessDocument(html);
  const state = createSuperappState();
  const previousDocument = globalThis.document;
  const previousFetch = globalThis.fetch;
  globalThis.document = documentHarness;
  globalThis.fetch = async (url) => {
    assert.equal(url, "/api/superapp-state");
    return {
      ok: true,
      async json() {
        return state;
      }
    };
  };

  try {
    await import(`../src/main.js?ui-render-test=${Date.now()}`);
    await new Promise((resolve) => setTimeout(resolve, 0));

    const textFor = (id) => documentHarness.elementsById.get(id).textContent;
    assert.equal(textFor("app-count"), "3");
    assert.match(textFor("discovered-apps"), /HermesChat/);
    assert.match(textFor("discovered-apps"), /MintNotes/);
    assert.match(textFor("discovered-apps"), /DailyMart/);
    assert.match(textFor("memory-list"), /payment_proof_policy/);
    assert.match(textFor("memory-list"), /privacy_policy/);
    assert.match(textFor("route-list"), /notes\.append_note/);
    assert.match(textFor("route-list"), /grocery\.purchase_essentials/);
    assert.match(textFor("execution-list"), /req-dailymart-demo-001/);
    assert.match(textFor("settlement-list"), /DailyMart/);
    assert.match(textFor("settlement-summary"), /Debits/);
    assert.equal(textFor("settlement-total"), "42.0000 OKRW");
  } finally {
    globalThis.document = previousDocument;
    globalThis.fetch = previousFetch;
  }
});
