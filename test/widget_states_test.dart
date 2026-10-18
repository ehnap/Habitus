import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habitus/src/copy/zh.dart';
import 'package:habitus/src/theme/habitus_theme.dart';
import 'package:habitus/src/ui/widgets.dart';

void main() {
  testWidgets('empty, loading, and error states use the Chinese copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: habitusLight(),
        home: const Scaffold(
          body: StatusPane(
            loading: false,
            empty: true,
            emptyTitle: Zh.noLibraryTitle,
            emptyBody: Zh.noLibraryBody,
            child: Text('hidden'),
          ),
        ),
      ),
    );
    expect(find.text(Zh.noLibraryTitle), findsOneWidget);
    expect(find.text('hidden'), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatusPane(
            loading: false,
            error: Exception('stack'),
            onRetry: () {},
            child: const Text('hidden'),
          ),
        ),
      ),
    );
    expect(find.text(Zh.genericError), findsOneWidget);
    expect(find.text(Zh.retry), findsOneWidget);
    expect(find.textContaining('stack'), findsNothing);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoadingPane())),
    );
    expect(find.byType(LoadingPane), findsOneWidget);
  });

  testWidgets('phone and desktop shells pick different navigation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: habitusLight(),
        home: const Scaffold(body: _LayoutProbe()),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: habitusLight(),
        home: const Scaffold(body: _LayoutProbe()),
      ),
    );
    expect(find.text('phone'), findsOneWidget);

    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(
      MaterialApp(
        theme: habitusLight(),
        home: const Scaffold(body: _LayoutProbe()),
      ),
    );
    expect(find.text('desktop'), findsOneWidget);
    await tester.binding.setSurfaceSize(null);
  });
}

class _LayoutProbe extends StatelessWidget {
  const _LayoutProbe();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Text(desktopLayout(constraints.maxWidth) ? 'desktop' : 'phone');
      },
    );
  }
}
