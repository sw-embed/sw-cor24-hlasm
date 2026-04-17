# Implementation Plan

## Goal
Restore the regression suite to a trustworthy green state before any new feature saga work continues.

## Step 1 -- Stabilize regressions
Fix broken regression fixtures and product bugs currently causing the suite to fail, starting with basic passthrough, blank-line handling, and macro-path breakage.

**Deliverable**: passing repo-local test suite with tracked baselines repaired as needed.

**Test**: ./build.sh test and targeted repo-local reg-rs runs pass.
