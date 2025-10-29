# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-10-29

### Added
- First public release establishing AITrace as an Elixir-native observability layer for AI agent workflows.
- Macro-based tracing DSL (`AITrace.trace/2`, `AITrace.span/2`) that captures nested spans and restores context across blocks.
- Structured event and attribute recording with `AITrace.add_event/2` and `AITrace.with_attributes/1`.
- Context propagation utilities and process dictionary helpers to correlate spans within complex control flow.
- Pluggable exporter pipeline with Console and File exporters for immediate inspection or archival of traces.
- Collector process and data model for Traces, Spans, and Events, designed to support future backends and real-time streaming.
