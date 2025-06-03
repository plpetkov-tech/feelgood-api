import json

with open('current-sbom.json') as f:
    current = json.load(f)
with open('base-sbom.json') as f:
    base = json.load(f)

current_components = {c['name']: c['version'] for c in current.get('components', [])}
base_components = {c['name']: c['version'] for c in base.get('components', [])}

added = set(current_components.keys()) - set(base_components.keys())
removed = set(base_components.keys()) - set(current_components.keys())
changed = {k for k in base_components if k in current_components and base_components[k] != current_components[k]}

with open('sbom_diff.txt', 'w') as out:
    if added:
        out.write('**Added:**\n')
        for pkg in added:
            out.write(f'- {pkg} {current_components[pkg]}\n')
    if removed:
        out.write('\n**Removed:**\n')
        for pkg in removed:
            out.write(f'- {pkg} {base_components[pkg]}\n')
    if changed:
        out.write('\n**Updated:**\n')
        for pkg in changed:
            out.write(f'- {pkg}: {base_components[pkg]} → {current_components[pkg]}\n') 