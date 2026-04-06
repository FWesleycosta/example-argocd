      # — SSM Parameters block —
      lines.append('')
      lines.append('ssm_parameters = {')
      for idx, p in enumerate(ssm_params):
          lines.append(f'  param_{idx} = {{')
          lines.append(f'    name  = "{p["name"]}"')
          lines.append(f'    value = "{p["value"]}"')
          lines.append(f'  }}')
      lines.append('}')
 
      with open(tfvars_path, 'w') as f:
          f.write('\n'.join(lines) + '\n')
 
      print('##[section] terraform.auto.tfvars gerado:')
      print('\n'.join(lines))
      PYEOF
    displayName: "Gerar terraform.auto.tfvars [${{ parameters.environment }}]"
