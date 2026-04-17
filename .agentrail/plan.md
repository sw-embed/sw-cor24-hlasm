# Implementation Plan

## Goal
Move sw-cor24-hlasm toward HLASM-like behavior on the MVS lineage while continuing structured control-flow work only on top of a green regression suite.

## Guardrails
- keep `./build.sh test` green before and after each step
- do not start new feature work on a red suite
- prefer IBM HLASM-like macro and structured-programming semantics over ad hoc behavior
- keep tracked `reg-rs` `.out` and `.rgt` artifacts current

## Step 1 -- HLASM Macro Semantics Baseline
Tighten macro-definition and invocation behavior toward HLASM-like expectations: definition lines suppressed from output, invocation expansion stable, and explicit compatibility notes for currently supported syntax.

**Deliverable**: documented and tested macro baseline matching the supported subset.

**Test**: `./build.sh test` plus targeted macro demos/regressions.

## Step 2 -- Parameterized Macro Compatibility
Implement reliable parameterized macro substitution in the supported HLASM-like form and update demos/tests away from known-bug placeholders.

**Deliverable**: passing parameterized macro demos and regressions.

**Test**: targeted parameterized-macro regressions plus full suite.

## Step 3 -- Macro Robustness And Multi-Macro State
Harden multiple macro definitions, repeated invocations, and local-label behavior so macro state matches HLASM-like expectations under repeated use.

**Deliverable**: stable multi-macro and local-label proofs.

**Test**: full regression suite and focused macro stress demos.

## Step 4 -- Structured Control-Flow Integration
Resume the structured IF/DO/SELECT integration pass only after macro compatibility is stable, and tighten combined proofs and docs around the supported subset.

**Deliverable**: integrated structured-control-flow proof using the compatibility-hardened macro engine.

**Test**: combined macro + conditional assembly + structured control-flow regression and full suite.
