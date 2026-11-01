import 'package:scoring/scoring.dart';
import 'package:test/test.dart';

void main() {
  test('strain words follow the easy / moderate / hard bands', () {
    expect(strainWord(0), 'Very light day');
    expect(strainWord(3.9), 'Very light day');
    expect(strainWord(4), 'Light day');
    expect(strainWord(7.9), 'Light day');
    expect(strainWord(8), 'Active day');
    expect(strainWord(13.9), 'Active day');
    expect(strainWord(14), 'Big day');
    expect(strainWord(18), 'All-out day');
    expect(strainWord(21), 'All-out day');
    // Same breaks as the coach's intensity for an unplanned workout.
    expect(intensityForStrain(7.9), Intensity.easy);
    expect(intensityForStrain(8), Intensity.moderate);
    expect(intensityForStrain(14), Intensity.hard);
  });
}
