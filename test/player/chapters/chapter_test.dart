import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/player/chapters/chapter.dart';

const _chapters = [
  MediaChapter(title: 'Intro', start: Duration.zero),
  MediaChapter(title: 'Acto 1', start: Duration(minutes: 2)),
  MediaChapter(title: 'Acto 2', start: Duration(minutes: 10)),
  MediaChapter(title: 'Créditos', start: Duration(minutes: 30)),
];

void main() {
  group('current chapter', () {
    test('is the last one that started at or before the position', () {
      expect(currentChapterIndex(_chapters, Duration.zero), 0);
      expect(currentChapterIndex(_chapters, const Duration(minutes: 1)), 0);
      expect(currentChapterIndex(_chapters, const Duration(minutes: 2)), 1);
      expect(currentChapterIndex(_chapters, const Duration(minutes: 9)), 1);
      expect(currentChapterIndex(_chapters, const Duration(hours: 2)), 3);
    });

    test('is -1 when there are no chapters at all', () {
      expect(currentChapterIndex(const [], const Duration(minutes: 5)), -1);
    });

    // A file whose first chapter does not start at zero leaves a gap before it.
    test('is -1 before the first chapter starts', () {
      const late = [MediaChapter(title: 'A', start: Duration(minutes: 5))];
      expect(currentChapterIndex(late, const Duration(minutes: 1)), -1);
    });
  });

  group('skipping forward', () {
    test('goes to the start of the next chapter', () {
      expect(nextChapterStart(_chapters, const Duration(minutes: 1)),
          const Duration(minutes: 2));
      expect(nextChapterStart(_chapters, const Duration(minutes: 11)),
          const Duration(minutes: 30));
    });

    test('is null in the last chapter, so the caller can do nothing', () {
      expect(nextChapterStart(_chapters, const Duration(minutes: 31)), isNull);
      expect(nextChapterStart(const [], Duration.zero), isNull);
    });
  });

  group('skipping back', () {
    // Same rule every music player uses: back restarts what you are in, and
    // only goes further back if you just started it.
    test('restarts the current chapter when you are into it', () {
      expect(previousChapterStart(_chapters, const Duration(minutes: 5)),
          const Duration(minutes: 2));
    });

    test('goes to the previous one when you just entered this one', () {
      expect(
        previousChapterStart(
            _chapters, const Duration(minutes: 2, seconds: 1)),
        Duration.zero,
      );
    });

    test('is null at the very start, with nowhere further back to go', () {
      expect(previousChapterStart(_chapters, const Duration(seconds: 1)), isNull);
      expect(previousChapterStart(const [], Duration.zero), isNull);
    });
  });

  group('seek-bar marks', () {
    test('are the chapter starts as a fraction of the whole', () {
      final marks = chapterMarks(_chapters, const Duration(minutes: 40));
      expect(marks, [0.05, 0.25, 0.75]);
    });

    test('skip a chapter starting at zero — the bar already begins there', () {
      final marks = chapterMarks(
        const [MediaChapter(title: 'A', start: Duration.zero)],
        const Duration(minutes: 10),
      );
      expect(marks, isEmpty);
    });

    test('are empty when the duration is unknown, instead of dividing by zero',
        () {
      expect(chapterMarks(_chapters, Duration.zero), isEmpty);
    });

    test('drop anything beyond the end rather than drawing off the bar', () {
      final marks = chapterMarks(_chapters, const Duration(minutes: 5));
      expect(marks, [0.4]);
    });
  });
}
