import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../llm/llm_client.dart';

enum LlmProvider { anthropic, gemini, openAiCompatible }

@immutable
class TerminaSettings {
  const TerminaSettings({
    this.provider = LlmProvider.anthropic,
    this.anthropicApiKey = '',
    this.anthropicModel = AnthropicClient.defaultModel,
    this.effort = 'medium',
    this.geminiApiKey = '',
    this.geminiModel = GeminiClient.defaultModel,
    this.openAiBaseUrl = 'http://localhost:11434/v1',
    this.openAiModel = 'qwen3-coder',
    this.openAiApiKey = '',
  });

  final LlmProvider provider;
  final String anthropicApiKey;
  final String anthropicModel;

  /// Thinking depth for Claude (`effort`) and Gemini (`thinkingLevel`).
  final String effort;
  final String geminiApiKey;
  final String geminiModel;
  final String openAiBaseUrl;
  final String openAiModel;
  final String openAiApiKey;

  /// The saved key, or `ANTHROPIC_API_KEY` from the environment.
  String get effectiveAnthropicKey => anthropicApiKey.isNotEmpty
      ? anthropicApiKey
      : Platform.environment['ANTHROPIC_API_KEY'] ?? '';

  /// The saved key, or `GEMINI_API_KEY` / `GOOGLE_API_KEY` from the
  /// environment.
  String get effectiveGeminiKey => geminiApiKey.isNotEmpty
      ? geminiApiKey
      : Platform.environment['GEMINI_API_KEY'] ??
            Platform.environment['GOOGLE_API_KEY'] ??
            '';

  bool get isConfigured => switch (provider) {
    LlmProvider.anthropic => effectiveAnthropicKey.isNotEmpty,
    LlmProvider.gemini => effectiveGeminiKey.isNotEmpty,
    LlmProvider.openAiCompatible =>
      openAiBaseUrl.isNotEmpty && openAiModel.isNotEmpty,
  };

  LlmClient createClient() => switch (provider) {
    LlmProvider.anthropic => AnthropicClient(
      apiKey: effectiveAnthropicKey,
      model: anthropicModel,
      effort: effort,
    ),
    LlmProvider.gemini => GeminiClient(
      apiKey: effectiveGeminiKey,
      model: geminiModel,
      thinkingLevel: effort,
    ),
    LlmProvider.openAiCompatible => OpenAiCompatibleClient(
      baseUrl: openAiBaseUrl,
      model: openAiModel,
      apiKey: openAiApiKey,
    ),
  };

  TerminaSettings copyWith({
    LlmProvider? provider,
    String? anthropicApiKey,
    String? anthropicModel,
    String? effort,
    String? geminiApiKey,
    String? geminiModel,
    String? openAiBaseUrl,
    String? openAiModel,
    String? openAiApiKey,
  }) => TerminaSettings(
    provider: provider ?? this.provider,
    anthropicApiKey: anthropicApiKey ?? this.anthropicApiKey,
    anthropicModel: anthropicModel ?? this.anthropicModel,
    effort: effort ?? this.effort,
    geminiApiKey: geminiApiKey ?? this.geminiApiKey,
    geminiModel: geminiModel ?? this.geminiModel,
    openAiBaseUrl: openAiBaseUrl ?? this.openAiBaseUrl,
    openAiModel: openAiModel ?? this.openAiModel,
    openAiApiKey: openAiApiKey ?? this.openAiApiKey,
  );

  static Future<TerminaSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    const defaults = TerminaSettings();
    return TerminaSettings(
      provider:
          LlmProvider.values.asNameMap()[prefs.getString('provider')] ??
          defaults.provider,
      anthropicApiKey: prefs.getString('anthropicApiKey') ?? '',
      anthropicModel:
          prefs.getString('anthropicModel') ?? defaults.anthropicModel,
      effort: prefs.getString('effort') ?? defaults.effort,
      geminiApiKey: prefs.getString('geminiApiKey') ?? '',
      geminiModel: prefs.getString('geminiModel') ?? defaults.geminiModel,
      openAiBaseUrl: prefs.getString('openAiBaseUrl') ?? defaults.openAiBaseUrl,
      openAiModel: prefs.getString('openAiModel') ?? defaults.openAiModel,
      openAiApiKey: prefs.getString('openAiApiKey') ?? '',
    );
  }

  Future<void> save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', provider.name);
    await prefs.setString('anthropicApiKey', anthropicApiKey);
    await prefs.setString('anthropicModel', anthropicModel);
    await prefs.setString('effort', effort);
    await prefs.setString('geminiApiKey', geminiApiKey);
    await prefs.setString('geminiModel', geminiModel);
    await prefs.setString('openAiBaseUrl', openAiBaseUrl);
    await prefs.setString('openAiModel', openAiModel);
    await prefs.setString('openAiApiKey', openAiApiKey);
  }
}
