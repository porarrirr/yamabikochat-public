"""Build GenUI assets from app-owned sources and pinned, licensed npm packages.

Outputs into ios/YamabikoChat/App/Resources/genui/:
- widget-components.js   app-owned widget implementations plus the interface contracts
- widget-sources.json    per-component implementation text served by genui_reference
- widget-tokens.js       procedurally generated Yamabiko design tokens (original values)
- lucide-icons.js        official lucide-static SVGs (ISC) plus incoming name aliases
- cel-runtime.js         @marcbachmann/cel-js (MIT) bundled for in-page CEL evaluation
- Lucide-LICENSE.txt / CEL-LICENSE.txt

The palette key names in palette-keys.json are the published interface; every
value is generated here from the Yamabiko hue choices below.
"""
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent
output = root.parent / 'YamabikoChat/App/Resources/genui'

# ---------------------------------------------------------------------------
# Yamabiko design tokens (original values, published key names)
# ---------------------------------------------------------------------------

# Raw scale families: hue and saturation chosen for this app.
FAMILIES = {
    'gray': (210, 5),
    'blue': (212, 66),
    'green': (150, 56),
    'orange': (26, 86),
    'pink': (338, 74),
    'purple': (266, 60),
    'red': (8, 72),
    'yellow': (44, 88),
    'teal': (168, 60),
}
CHROMATIC_STEPS = [25, 50, 75, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950, 1000]
GRAY_STEPS = [0, 25, 50, 75, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600, 650,
              700, 750, 800, 850, 900, 925, 950, 975, 1000]
# Lightness ramp shared by chromatic families (step -> lightness %).
CHROMATIC_LIGHTNESS = {25: 97, 50: 95, 75: 92, 100: 89, 200: 82, 300: 72, 400: 60,
                       500: 49, 600: 41, 700: 33, 800: 26, 900: 20, 950: 14, 1000: 9}
GRAY_LIGHTNESS = {0: 99, 25: 97, 50: 95, 75: 93, 100: 90, 150: 86, 200: 81, 250: 76,
                  300: 70, 350: 64, 400: 57, 450: 50, 500: 44, 550: 38, 600: 32,
                  650: 27, 700: 22, 750: 18, 800: 15, 850: 12, 900: 10, 925: 8,
                  950: 7, 975: 6, 1000: 5}

def clamp(value, low=0, high=100):
    return max(low, min(high, value))

def hsl_css(hue, saturation, lightness, alpha=1):
    """Return an hsl() string; keeps generated values readable and diffable."""
    if alpha >= 1:
        return f'hsl({hue} {saturation}% {lightness}%)'
    return f'hsl({hue} {saturation}% {lightness}% / {round(alpha, 3)})'

def scale(family, step, alpha=1):
    hue, saturation = FAMILIES[family]
    if family == 'gray':
        lightness = GRAY_LIGHTNESS[step]
    else:
        lightness = CHROMATIC_LIGHTNESS[step]
    # Slightly soften saturation at the extremes to avoid neon or muddy ends.
    effective = saturation * (0.82 if step <= 75 else 0.9 if step >= 900 else 1.0)
    return hsl_css(hue, round(clamp(effective), 1), lightness, alpha)

def foreground(theme):
    return scale('teal', 1000 if theme == 'light' else 25)

def raw_scales():
    # The teal brand ramp feeds semantic rules only; the shipped raw scale keys
    # stay exactly the published key set.
    palette = {}
    for family, steps in [('gray', GRAY_STEPS)] + [(name, CHROMATIC_STEPS) for name in FAMILIES if name not in ('gray', 'teal')]:
        for step in steps:
            palette[f'{family}-{step}'] = scale(family, step)
        if family != 'gray':
            # Alpha variants: a25..a75 fade the mid tone; a100..a300 step brighter.
            palette[f'{family}-a25'] = scale(family, 500, 0.25)
            palette[f'{family}-a50'] = scale(family, 500, 0.5)
            palette[f'{family}-a75'] = scale(family, 500, 0.75)
            palette[f'{family}-a100'] = scale(family, 400)
            palette[f'{family}-a200'] = scale(family, 300)
            palette[f'{family}-a300'] = scale(family, 200)
    return palette

# Semantic tones -> raw family.
TONES = {'primary': 'teal', 'secondary': 'gray', 'info': 'blue', 'success': 'green',
         'warning': 'yellow', 'danger': 'red', 'caution': 'orange', 'discovery': 'purple'}

def tone(family, theme, variant):
    """Pick a scale step for a semantic background/text role."""
    if theme == 'light':
        return {'solid': 600, 'solid-hover': 700, 'solid-active': 800,
                'soft-text': 700, 'outline-text': 600, 'ghost-text': 600}[variant]
    return {'solid': 500, 'solid-hover': 400, 'solid-active': 300,
            'soft-text': 300, 'outline-text': 300, 'ghost-text': 300}[variant]

def alpha_of(family, step, theme, alpha):
    return scale(family, step, alpha)

def build_semantic_keys(keys):
    light, dark = {}, {}
    surfaces = {
        'light': {'surface': scale('teal', 25), 'surface-secondary': scale('teal', 100),
                  'surface-soft': scale('teal', 50), 'surface-tertiary': scale('teal', 100),
                  'surface-elevated': 'hsl(0 0% 100%)', 'surface-elevated-secondary': scale('teal', 75)},
        'dark': {'surface': 'hsl(180 6% 7%)', 'surface-secondary': 'hsl(180 6% 5%)',
                 'surface-soft': 'hsl(180 6% 9%)', 'surface-tertiary': 'hsl(180 6% 12%)',
                 'surface-elevated': 'hsl(168 5% 10%)', 'surface-elevated-secondary': 'hsl(168 5% 14%)'},
    }
    text = {
        'light': {'primary': scale('teal', 1000), 'secondary': scale('teal', 700, 0.75),
                  'tertiary': scale('teal', 700, 0.55), 'prose': scale('teal', 950),
                  'emphasis': 'hsl(0 0% 0%)', 'inverse': 'hsl(0 0% 100%)'},
        'dark': {'primary': scale('teal', 50), 'secondary': scale('teal', 300, 0.7),
                 'tertiary': scale('teal', 300, 0.5), 'prose': scale('teal', 100),
                 'emphasis': 'hsl(0 0% 100%)', 'inverse': scale('teal', 1000)},
    }
    code = {
        'light': {'foreground': scale('teal', 950), 'comment': scale('gray', 500),
                  'keyword': 'hsl(266 60% 40%)', 'string': 'hsl(150 56% 28%)',
                  'number': 'hsl(26 86% 38%)', 'function': 'hsl(212 66% 38%)',
                  'property': 'hsl(168 60% 30%)', 'punctuation': scale('gray', 600)},
        'dark': {'foreground': scale('teal', 100), 'comment': scale('gray', 450),
                 'keyword': 'hsl(266 60% 74%)', 'string': 'hsl(150 56% 66%)',
                 'number': 'hsl(26 86% 68%)', 'function': 'hsl(212 66% 70%)',
                 'property': 'hsl(168 60% 62%)', 'punctuation': scale('gray', 400)},
    }
    for theme, palette in [('light', light), ('dark', dark)]:
        palette.update(raw_scales())
        fg = foreground(theme)
        palette.update(surfaces[theme])
        palette.update({name: value for name, value in text[theme].items() if name != 'inverse'})
        palette.update({f'color-code-{name}': value for name, value in code[theme].items()})
        palette.update({f'color-{name}': value for name, value in surfaces[theme].items()})
        palette['color-text'] = text[theme]['primary']
        palette['color-text-emphasis'] = text[theme]['emphasis']
        palette['color-text-prose'] = text[theme]['prose']
        palette['color-text-tertiary'] = text[theme]['tertiary']
        palette['black'] = 'hsl(0 0% 0%)'
        palette['white'] = 'hsl(0 0% 100%)'
        palette['base'] = fg
        palette['none'] = 'transparent'
        palette['transparent'] = 'transparent'
        # Foreground alpha ramp; single digits below 10 keep the zero-padded key names.
        ramp_lightness = 9 if theme == 'light' else 95
        for step in [0, 1, 2, 4, 5, 6, 8, 10, 12, 15, 16, 20, 25, 30, 35, 40, 50, 60, 70]:
            name = f'alpha-{step:02d}' if 0 < step < 10 else f'alpha-{step}'
            palette[name] = f'hsl(168 60% {ramp_lightness}% / {step / 100})'
        palette['color-border'] = palette['alpha-10']
        palette['color-border-strong'] = palette['alpha-25']
        palette['color-border-subtle'] = palette['alpha-06']
        palette['color-border-disabled'] = palette['alpha-08']
        palette['color-background-disabled'] = palette['alpha-06']
        palette['color-text-disabled'] = palette['alpha-30']
        palette['color-text-inverse'] = text[theme]['inverse']
        palette['color-ring'] = palette['alpha-25']
        palette['default'] = palette['color-border']
        palette['emphasis'] = text[theme]['primary']
        palette['strong'] = text[theme]['primary']
        palette['subtle'] = text[theme]['secondary']
        for bare in ['primary', 'secondary', 'tertiary', 'danger', 'warning', 'success']:
            if bare == 'tertiary':
                palette[bare] = text[theme]['tertiary']
            else:
                palette[bare] = palette.get(f'color-text-{bare}', text[theme]['primary'])
        for tone_name, family in TONES.items():
            solid = tone(family, theme, 'solid')
            soft_text = tone(family, theme, 'soft-text')
            outline_text = tone(family, theme, 'outline-text')
            ghost_text = tone(family, theme, 'ghost-text')
            soft_alpha, hover_alpha, active_alpha = (0.10, 0.16, 0.22) if theme == 'light' else (0.16, 0.22, 0.28)
            faint_alpha, faint_hover, faint_active = (0.05, 0.09, 0.13) if theme == 'light' else (0.08, 0.12, 0.16)
            palette[f'color-background-{tone_name}-solid'] = scale(family, solid)
            palette[f'color-background-{tone_name}-solid-hover'] = scale(family, tone(family, theme, 'solid-hover'))
            palette[f'color-background-{tone_name}-solid-active'] = scale(family, tone(family, theme, 'solid-active'))
            palette[f'color-text-{tone_name}-solid'] = (
                scale(family, 1000) if theme == 'dark' else 'hsl(0 0% 100%)')
            palette[f'color-background-{tone_name}-soft'] = alpha_of(family, 500, theme, soft_alpha)
            palette[f'color-background-{tone_name}-soft-hover'] = alpha_of(family, 500, theme, hover_alpha)
            palette[f'color-background-{tone_name}-soft-active'] = alpha_of(family, 500, theme, active_alpha)
            palette[f'color-background-{tone_name}-soft-alpha'] = alpha_of(family, 500, theme, faint_alpha)
            palette[f'color-background-{tone_name}-soft-alpha-hover'] = alpha_of(family, 500, theme, faint_hover)
            palette[f'color-background-{tone_name}-soft-alpha-active'] = alpha_of(family, 500, theme, faint_active)
            if tone_name != 'secondary':
                palette[f'color-background-{tone_name}-surface'] = alpha_of(family, 500, theme, 0.06 if theme == 'light' else 0.09)
                palette[f'color-text-{tone_name}-surface'] = scale(family, soft_text)
                palette[f'color-border-{tone_name}-surface'] = alpha_of(family, 500, theme, 0.15)
            palette[f'color-text-{tone_name}'] = scale(family, soft_text)
            palette[f'color-text-{tone_name}-soft'] = scale(family, soft_text)
            palette[f'color-text-{tone_name}-outline'] = scale(family, outline_text)
            palette[f'color-text-{tone_name}-outline-hover'] = scale(family, outline_text)
            palette[f'color-text-{tone_name}-ghost'] = scale(family, ghost_text)
            palette[f'color-text-{tone_name}-ghost-hover'] = scale(family, ghost_text)
            if tone_name == 'caution':
                palette['color-text-caution-hover'] = scale(family, outline_text)
            palette[f'color-border-{tone_name}-outline'] = alpha_of(family, 500, theme, 0.45 if theme == 'light' else 0.5)
            palette[f'color-border-{tone_name}-outline-hover'] = alpha_of(family, 500, theme, 0.7 if theme == 'light' else 0.75)
            palette[f'color-ring-{tone_name}'] = alpha_of(family, 500, theme, 0.4 if theme == 'light' else 0.45)
            for variant in ['solid', 'soft', 'ghost', 'outline']:
                ring_alpha = 0.35 if theme == 'light' else 0.4
                palette[f'color-ring-{tone_name}-{variant}'] = alpha_of(family, solid if variant == 'solid' else 500, theme, ring_alpha)
            palette[f'color-background-{tone_name}-ghost-hover'] = alpha_of(family, 500, theme, 0.08 if theme == 'light' else 0.12)
            palette[f'color-background-{tone_name}-ghost-active'] = alpha_of(family, 500, theme, 0.12 if theme == 'light' else 0.16)
            palette[f'color-background-{tone_name}-outline-hover'] = alpha_of(family, 500, theme, 0.08 if theme == 'light' else 0.12)
            palette[f'color-background-{tone_name}-outline-active'] = alpha_of(family, 500, theme, 0.12 if theme == 'light' else 0.16)
        # soft-alt exists only for primary/secondary in the published key set.
        for tone_name in ['primary', 'secondary']:
            family = TONES[tone_name]
            palette[f'color-background-{tone_name}-soft-alt'] = alpha_of(family, 500, theme, 0.07)
            palette[f'color-text-{tone_name}-soft-alt'] = scale(family, tone(family, theme, 'soft-text'))
            palette[f'color-border-{tone_name}-soft-alt'] = alpha_of(family, 500, theme, 0.2)
    return light, dark

def build_tokens():
    keys = json.loads((root / 'palette-keys.json').read_text())['keys']
    light, dark = build_semantic_keys(keys)
    missing = [key for key in keys if key not in light or key not in dark]
    if missing:
        raise SystemExit(f'palette rules missing keys: {missing[:8]}')
    extra = [key for key in light if key not in keys]
    if extra:
        raise SystemExit(f'palette rules produced unknown keys: {extra[:8]}')
    light = {key: light[key] for key in keys}
    dark = {key: dark[key] for key in keys}
    typography = {
        'text': {'3xs': {'fontSize': 11, 'lineHeight': 13}, '2xs': {'fontSize': 11, 'lineHeight': 13},
                 'xs': {'fontSize': 13, 'lineHeight': 18}, 'sm': {'fontSize': 15, 'lineHeight': 20},
                 'md': {'fontSize': 17, 'lineHeight': 24}, 'lg': {'fontSize': 17, 'lineHeight': 24},
                 'xl': {'fontSize': 20, 'lineHeight': 26}},
        'title': {'xs': {'fontSize': 17, 'lineHeight': 24}, 'sm': {'fontSize': 17, 'lineHeight': 24},
                  'md': {'fontSize': 19, 'lineHeight': 26}, 'lg': {'fontSize': 20, 'lineHeight': 26},
                  'xl': {'fontSize': 22, 'lineHeight': 28}, '2xl': {'fontSize': 28, 'lineHeight': 34},
                  '3xl': {'fontSize': 32, 'lineHeight': 38}, '4xl': {'fontSize': 34, 'lineHeight': 40},
                  '5xl': {'fontSize': 34, 'lineHeight': 40}},
        'caption': {'sm': {'fontSize': 11, 'lineHeight': 14}, 'md': {'fontSize': 12, 'lineHeight': 16},
                    'lg': {'fontSize': 13, 'lineHeight': 17}},
        'code': {'fontSize': 13, 'lineHeight': 18, 'fontFamily': 'Menlo-Regular'},
        'markdown': {'headingSizes': ['xl', 'lg', 'sm', 'xs', 'xs', 'xs'],
                     'headingWeight': 'semibold', 'strongWeight': 'semibold'},
    }
    text_input = lambda font, gutter, radius: {'fontSize': font, 'gutter': gutter, 'borderRadius': radius}
    control_metrics = {
        '3xs': {'height': 22, 'fontSize': 12, 'textInput': text_input(12, 8, 6), 'icon': 16, 'buttonIcon': 18},
        '2xs': {'height': 24, 'fontSize': 12, 'textInput': text_input(12, 8, 6), 'icon': 16, 'buttonIcon': 18},
        'xs': {'height': 26, 'fontSize': 14, 'textInput': text_input(14, 8, 6), 'icon': 12, 'buttonIcon': 18},
        'sm': {'height': 28, 'fontSize': 14, 'textInput': text_input(14, 10, 7), 'icon': 14, 'buttonIcon': 16},
        'md': {'height': 32, 'fontSize': 14, 'textInput': text_input(14, 12, 8), 'icon': 16, 'buttonIcon': 18},
        'lg': {'height': 36, 'fontSize': 15, 'textInput': text_input(15, 12, 8), 'icon': 18, 'buttonIcon': 20},
        'xl': {'height': 40, 'fontSize': 16, 'textInput': text_input(16, 14, 10), 'icon': 20, 'buttonIcon': 22},
        '2xl': {'height': 44, 'fontSize': 16, 'textInput': text_input(16, 16, 12), 'icon': 24, 'buttonIcon': 24},
        '3xl': {'height': 48, 'fontSize': 17, 'textInput': text_input(17, 16, 12), 'icon': 32, 'buttonIcon': 18},
    }
    return {'LIGHT_COLOR_PALETTE': light, 'DARK_COLOR_PALETTE': dark,
            'typography': typography, 'controlMetrics': control_metrics}

# ---------------------------------------------------------------------------
# Widget families: the dispatch rules mirrored from widgets.js so genui_reference
# can serve the implementation text that actually renders each component name.
# ---------------------------------------------------------------------------

DISPATCH = [
    (r'^Digital(Timer|Stopwatch)Widget$', 'timer'),
    (r'^ClockWidget$', 'clock'),
    (r'^CurrencyConverter', 'currency'),
    (r'^UnitConverter', 'unit'),
    (r'^ChecklistWidget$', 'checklist'),
    (r'^(?:Learning|Open|Update)\w*Flashcards$', 'flashcards'),
    (r'^(?:WordCard|CopyWords)Widget$', 'wordcard'),
    (r'^(?:LearningQuiz|FollowUpQuiz|MultipleChoiceBlockV2)$', 'quiz'),
    (r'^AskUser', 'askuser'),
    (r'^(?:FollowUp|ConversationFollowUpActionList|PluginFollowup)', 'followup'),
    (r'^(?:Weather|WeatherCurrent)', 'weather'),
    (r'^PromptChecklist$', 'tasks'),
    (r'^Tab(?:Group|bedSectionWidget)$', 'tabs'),
    (r'^(?:PackageTracker(?:Widget)?)$', 'tracker'),
    (r'^FlightTrackerWidget$', 'tracker'),
    (r'^Election(?:Info|Results(?:Widget)?)$', 'election'),
    (r'^Reddit(?:From\w+)?$', 'reddit'),
    (r'^ImageGenWidget$', 'image'),
    (r'^StockQuote(?:Comparison)?Widget$', 'stocks'),
    (r'^Stock(?:Comparison)?Chart$', 'stocks'),
    (r'^Ledger(?:Recent|Upcoming|Recurring)Transactions?\w*$', 'ledger'),
    (r'^Ledger\w*$', 'ledger'),
    (r'^CalculatorWidget$', 'calculator'),
    (r'^Calculator', 'medical'),
    (r'^(?:Nba|Nfl|Nhl|Mlb|Epl|Ipl|Ncaamb|Ncaawb|Wnba|Cfb|Cricket|Tennis|Soccer|Basketball|MarchMadness|Superbowl)\w*(?:Standings)\w*$', 'sports'),
    (r'^(?:Nba|Nfl|Nhl|Mlb|Epl|Ipl|Ncaamb|Ncaawb|Wnba|Cfb|Cricket|Tennis|Soccer|Basketball|MarchMadness|Superbowl)\w*(?:Scores|Boxscore|Games?|Schedule)\w*$', 'sports'),
]

def widget_families(names):
    families = {}
    for name in names:
        for pattern, family in DISPATCH:
            if re.search(pattern, name):
                families[name] = family
                break
        else:
            families[name] = 'generic'
    return families

def build_sources(contracts):
    widgets = (root / 'widgets.js').read_text()
    markers = list(re.finditer(r'    // === family: (\w+) ===\n', widgets))
    dispatch_start = widgets.index('    // === dispatch ===')
    sections = {}
    for index, marker in enumerate(markers):
        end = markers[index + 1].start() if index + 1 < len(markers) else dispatch_start
        sections[marker.group(1)] = widgets[marker.start():end].rstrip() + '\n'
    shared = sections.pop('shared')
    families = widget_families(sorted(contracts))
    missing = [name for name, family in families.items() if family not in sections]
    if missing:
        raise SystemExit(f'widget family sections missing: {sorted(set(missing))[:8]}')
    sources = {name: shared + sections[families[name]] for name in sorted(contracts)}
    return sources

# ---------------------------------------------------------------------------
# Icons: official lucide-static SVGs plus incoming-name aliases.
# ---------------------------------------------------------------------------

def svg_node(node):
    return {'tag': node.tag.split('}')[-1], 'attrs': dict(node.attrib),
            'children': [svg_node(child) for child in node]}

def build_icons():
    lucide = root / 'node_modules/lucide-static'
    icons = {path.stem: svg_node(ET.parse(path).getroot())
             for path in sorted((lucide / 'icons').glob('*.svg'))}
    aliases = json.loads((root / 'icon-aliases.json').read_text())
    unresolved = sorted({target for target in aliases.values() if target not in icons})
    if unresolved:
        raise SystemExit(f'icon aliases point at missing Lucide icons: {unresolved[:8]}')
    return {'icons': icons, 'aliases': aliases}

def patch_cel_bundle(path):
    """Align cel-js numeric semantics with the document runtime contract.

    Documents evaluate every number as a JS double: int/int division is
    real division (7/2 -> 3.5) and zero-division errors read 'Division by
    zero'. cel-js truncates int/int and lower-cases those messages; patch the
    bundled handlers so documents keep behaving identically. cel.test.js covers
    both behaviors.
    """
    source = path.read_text()
    replacements = [
        ('binaryOverload("int", "/", "int", (a, b, ast) => {\n      if (b === MIN_UINT) return throwDivisionByZero(ast);\n      return a / b;\n    });',
         'binaryOverload("int", "/", "int", (a, b, ast) => {\n      if (b === MIN_UINT) return throwDivisionByZero(ast);\n      return Number(a) / Number(b);\n    });'),
        ('binaryOverload("double", "/", "double", (a, b) => a / b);',
         'binaryOverload("double", "/", "double", (a, b) => {\n      if (Number(b) === 0) throw evaluationError("division_by_zero", "Division by zero", undefined);\n      return a / b;\n    });'),
        ('evaluationError("division_by_zero", "division by zero", ast)',
         'evaluationError("division_by_zero", "Division by zero", ast)'),
        ('evaluationError("modulo_by_zero", "modulo by zero", ast)',
         'evaluationError("modulo_by_zero", "Modulo by zero", ast)'),
    ]
    for old, new in replacements:
        if source.count(old) != 1:
            raise SystemExit(f'cel bundle patch target not found exactly once: {old[:60]}...')
        source = source.replace(old, new)
    path.write_text(source)

def main():
    output.mkdir(parents=True, exist_ok=True)
    contracts = json.loads((root / 'contracts.json').read_text())
    components = (root / 'widgets.js').read_text()
    sources = build_sources(contracts)
    names = sorted(contracts)
    (output / 'widget-components.js').write_text(
        '// YamabikoChat app-owned GenUI widget implementations. Generated by ios/GenUIAssets/build.py; edit the sources there.\n'
        'globalThis.__GENUI_WIDGET_COMPONENT_NAMES__ = ' + json.dumps(names, ensure_ascii=False) + ';\n'
        + components)
    (output / 'widget-sources.json').write_text(json.dumps(sources, ensure_ascii=False) + '\n')
    tokens = build_tokens()
    (output / 'widget-tokens.js').write_text(
        '// Yamabiko design tokens generated by ios/GenUIAssets/build.py (original values; published key names).\n'
        'globalThis.__GENUI_WIDGET_TOKENS__ = ' + json.dumps(tokens, ensure_ascii=False, separators=(',', ':')) + ';\n')
    subprocess.run([str(root / 'node_modules/.bin/esbuild'), str(root / 'cel-entry.js'),
                    '--bundle', '--format=iife', '--target=safari17', '--legal-comments=inline',
                    '--outfile=' + str(output / 'cel-runtime.js')], check=True)
    patch_cel_bundle(output / 'cel-runtime.js')
    icons = build_icons()
    (output / 'lucide-icons.js').write_text(
        '// Official Lucide icons via lucide-static 1.61.0 (ISC). See Lucide-LICENSE.txt.\n'
        'globalThis.__GENUI_WIDGET_ICONS__ = '
        + json.dumps(icons, separators=(',', ':')) + ';\n')
    for package, filename in [('lucide-static', 'Lucide-LICENSE.txt'), ('@marcbachmann/cel-js', 'CEL-LICENSE.txt')]:
        (output / filename).write_text((root / 'node_modules' / package / 'LICENSE').read_text())
    print(f'Built {len(contracts)} widget contracts, {len(tokens["LIGHT_COLOR_PALETTE"])} palette keys, '
          f'{len(icons["icons"])} Lucide icons, {len(icons["aliases"])} incoming aliases.')

if __name__ == '__main__':
    main()
