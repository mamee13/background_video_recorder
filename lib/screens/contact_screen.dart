import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  Future<void> _launch(BuildContext context, Uri uri) async {
    final supported = await canLaunchUrl(uri);
    if (!supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No application available to open this link')),
      );
      return;
    }
    final mode = uri.scheme == 'mailto' ? LaunchMode.externalApplication : LaunchMode.platformDefault;
    final ok = await launchUrl(uri, mode: mode);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Contact')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero header uses free vertical space
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primary.withOpacity(0.15), cs.secondary.withOpacity(0.20)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.support_agent, color: cs.onPrimaryContainer, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'I am here to help',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Contact me for support, feedback, or feature requests.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action cards
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ContactCard(
                  icon: Icons.email_outlined,
                  title: 'Email',
                  subtitle: 'mamaruyirga1394@gmail.com',
                  onTap: () => _launch(context, Uri.parse('mailto:mamaruyirga1394@gmail.com?subject=Background%20Video%20Recorder%20Support')),
                ),
                _ContactCard(
                  icon: Icons.language_outlined,
                  title: 'Website',
                  subtitle: 'here is my website',
                  onTap: () => _launch(context, Uri.parse('https://my-portfolio-five-olive-23.vercel.app/')),
                ),
                _ContactCard(
                  icon: Icons.alternate_email,
                  title: 'Twitter / X',
                  subtitle: 'https://x.com/mamee1313',
                  onTap: () => _launch(context, Uri.parse('https://x.com/mamee1313')),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Quick actions row
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _launch(context, Uri.parse('mailto:mamaruyirga1394@gmail.com?subject=Background%20Video%20Recorder%20Support')),
                    icon: const Icon(Icons.send),
                    label: const Text('Email Support'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _launch(context, Uri.parse('https://my-portfolio-five-olive-23.vercel.app/')),
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Visit Website'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            Text(
              'I typically respond within 1–2 business days.    Mamaru Yirga',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ContactCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 500, // allows Wrap to arrange in 1–2 columns depending on width
      child: Card(
        color: cs.surfaceVariant.withOpacity(0.8),
        child: ListTile(
          leading: Icon(icon, size: 28),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.open_in_new),
          onTap: onTap,
        ),
      ),
    );
  }
}