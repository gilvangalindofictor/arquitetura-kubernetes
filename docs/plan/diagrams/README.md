# Diagramas da Plataforma EKS GitLab

Esta pasta contém os diagramas técnicos da arquitetura AWS EKS GitLab Platform.

## Arquivos SVG (Prontos para Uso)

Estes arquivos são utilizados diretamente no documento markdown e renderizam corretamente em PDFs:

### 1. gitlab-eks-platform.svg
**Diagrama principal da arquitetura completa**
- Visão geral end-to-end da plataforma
- Mostra todos os componentes: GitLab, Observability, Node Groups, Managed Services
- Inclui namespaces, conexões e fluxos de dados
- Legenda completa com cores para cada tipo de componente

### 2. vpc-network-architecture.svg
**Arquitetura de rede VPC**
- 3 Availability Zones (us-east-1a/b/c)
- Subnets públicas, privadas e de dados
- NAT Gateways e Internet Gateway
- Node groups e serviços gerenciados
- Conexões de rede entre componentes

### 3. security-groups.svg
**Security Groups e fluxo de tráfego**
- Security Groups e suas relações
- Fluxo de tráfego com portas específicas
- WAF, IP allowlist
- Regras de ingress/egress
- Best practices de segurança

## Arquivos Mermaid (Fonte)

Arquivos `.mmd` são os arquivos fonte em formato Mermaid Markdown:

- `gitlab_eks_platform.mmd` - Fonte do diagrama principal (deprecado, usar SVG)
- `vpc-network-architecture.mmd` - Fonte da arquitetura VPC
- `security-groups.mmd` - Fonte dos security groups

**Nota**: Os arquivos Mermaid são mantidos para referência, mas os SVGs são a versão final usada na documentação.

## Utilizando os Diagramas

### No Markdown
```markdown
![Descrição](diagrams/nome-do-arquivo.svg)
```

### Editando os SVGs
Os arquivos SVG foram criados manualmente para garantir compatibilidade máxima com conversores PDF. Para editar:

1. Abra o arquivo `.svg` em um editor de texto
2. Modifique os elementos SVG (formas, textos, cores)
3. Teste a renderização em navegador antes de usar no documento

### Gerando PDFs
Os arquivos SVG renderizam corretamente em:
- Navegadores modernos
- Conversores markdown-to-PDF (pandoc, wkhtmltopdf, etc)
- Viewers de PDF modernos

## Cores Utilizadas (Padrão)

- **GitLab Components**: #FF9800 (laranja)
- **Observability Stack**: #00BCD4 (ciano)
- **EKS Infrastructure**: #1976D2 / #3F51B5 (azul)
- **AWS Managed Services**: #FF9800 (laranja escuro)
- **Network (Public)**: #4CAF50 (verde)
- **Network (Private)**: #2196F3 (azul)
- **Network (Data)**: #FF9800 (laranja)
- **Security**: #E74C3C (vermelho)
- **Storage**: #9C27B0 (roxo)

## Manutenção

Ao atualizar a arquitetura:
1. Atualize os arquivos SVG correspondentes
2. Verifique a renderização no documento markdown
3. Teste a geração do PDF
4. Atualize este README se novos diagramas forem adicionados
