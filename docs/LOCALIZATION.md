# Localization

LanFi uses standard `.lproj/Localizable.strings` files. English source keys live in
`Resources/en.lproj/Localizable.strings`; Russian is in
`Resources/ru.lproj/Localizable.strings`. German, French and Simplified Chinese
live alongside in `de.lproj`, `fr.lproj` and `zh-Hans.lproj`; all five locales
are declared in `CFBundleLocalizations` in `project.yml`.

## Add a language

1. Copy `Resources/en.lproj/Localizable.strings` to
   `Resources/<language>.lproj/Localizable.strings`.
2. Translate only the right-hand side. Keep keys and format specifiers unchanged.
3. Add the language to the Xcode project resources and `CFBundleLocalizations`
   if needed.
4. Run `xcodegen generate`, build and check the UI.

Missing keys fall back to the English key. Do not machine-translate legal,
security or safety text without review.
