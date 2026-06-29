import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kivo_player/core/icons/kivo_icons.dart';
import 'package:kivo_player/ui/player/state/aspect_state.dart';

void main() {
  test('nextAspect cycles fit->fill->stretch->fit', () {
    expect(nextAspect(AspectMode.fit), AspectMode.fill);
    expect(nextAspect(AspectMode.fill), AspectMode.stretch);
    expect(nextAspect(AspectMode.stretch), AspectMode.fit);
  });
  test('boxFitFor maps modes', () {
    expect(boxFitFor(AspectMode.fit), BoxFit.contain);
    expect(boxFitFor(AspectMode.fill), BoxFit.cover);
    expect(boxFitFor(AspectMode.stretch), BoxFit.fill);
  });
  test('aspectFromSetting parses, defaults to fit', () {
    expect(aspectFromSetting('fill'), AspectMode.fill);
    expect(aspectFromSetting('stretch'), AspectMode.stretch);
    expect(aspectFromSetting('16:9'), AspectMode.fit);
  });
  test('aspectIconFor returns the correct icon per mode', () {
    expect(aspectIconFor(AspectMode.fit), KivoIcons.aspectFit);
    expect(aspectIconFor(AspectMode.fill), KivoIcons.aspectFill);
    expect(aspectIconFor(AspectMode.stretch), KivoIcons.aspectStretch);
  });
  test('aspectLabelFor returns the correct label per mode', () {
    expect(aspectLabelFor(AspectMode.fit), 'Ajustar');
    expect(aspectLabelFor(AspectMode.fill), 'Llenar');
    expect(aspectLabelFor(AspectMode.stretch), 'Estirar');
  });
}
