// Bottom-sheet flow for reporting correction issues.
//
// Builds report payloads from active request metadata and opens
// external contact channels (email or Telegram) from one place.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';

/// Report problem sheet for the active correction.
class ReportSheet extends StatefulWidget {
  const ReportSheet({required this.state, super.key});

  final AppState state;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  final TextEditingController _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestId = widget.state.requestId?.isNotEmpty ?? false
        ? widget.state.requestId!
        : widget.state.t('report.notAvailable');
    final hasEmail = widget.state.config.reportEmail.isNotEmpty;
    final hasTelegram = widget.state.config.reportTelegramUrl.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.state.t('report.title'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(widget.state.t('report.body')),
                  const SizedBox(height: 12),
                  SelectableText(
                    widget.state.t(
                      'report.requestId',
                      vars: {'requestId': requestId},
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _detailsController,
                    minLines: 2,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: widget.state.t('report.detailsLabel'),
                      hintText: widget.state.t('report.detailsHint'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: hasEmail
                            ? () => _launchEmail(context)
                            : null,
                        icon: const Icon(Icons.email_outlined),
                        label: Text(widget.state.t('report.email')),
                      ),
                      OutlinedButton.icon(
                        onPressed: hasTelegram
                            ? () => _launchTelegram(context)
                            : null,
                        icon: const Icon(Icons.send_outlined),
                        label: Text(widget.state.t('report.telegram')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(widget.state.t('actions.close')),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Launch the mail client with a prefilled report.
  Future<void> _launchEmail(BuildContext context) async {
    final uri = _buildEmailUri();
    await _launchExternal(context, uri);
  }

  /// Launch Telegram using the configured URL.
  Future<void> _launchTelegram(BuildContext context) async {
    final uri = Uri.parse(widget.state.config.reportTelegramUrl);
    await _launchExternal(context, uri);
  }

  /// Build the mailto URI with request metadata.
  Uri _buildEmailUri() {
    final requestId = widget.state.requestId?.isNotEmpty ?? false
        ? widget.state.requestId!
        : widget.state.t('report.notAvailable');
    final timestamp = DateTime.now().toIso8601String();
    final backend =
        (widget.state.modelBackend != null &&
            widget.state.modelBackend!.isNotEmpty)
        ? widget.state.modelBackend!
        : (widget.state.config.baseUrl.isNotEmpty
              ? widget.state.config.baseUrl
              : widget.state.t('report.unknown'));
    final subject = widget.state.t(
      'report.emailSubject',
      vars: {'appName': widget.state.config.appName},
    );
    var body = widget.state.t(
      'report.emailBody',
      vars: {
        'requestId': requestId,
        'timestamp': timestamp,
        'backend': backend,
      },
    );
    final details = _detailsController.text.trim();
    if (details.isNotEmpty) {
      body = '$body\n\n${widget.state.t('report.detailsLabel')}: $details';
    }

    return Uri(
      scheme: 'mailto',
      path: widget.state.config.reportEmail,
      queryParameters: {'subject': subject, 'body': body},
    );
  }

  /// Open a link in an external application.
  Future<void> _launchExternal(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.state.t('errors.openLink'))),
      );
    }
  }
}
