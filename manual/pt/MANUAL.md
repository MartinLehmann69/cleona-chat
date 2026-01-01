# Cleona Chat -- Manual do Usuário

Versão 3.1.125 | Julho de 2026

---

## Índice

1. [O que é o Cleona Chat?](#1-o-que-e-o-cleona-chat)
2. [Primeiros passos](#2-primeiros-passos)
3. [Contactos](#3-contactos)
4. [Mensagens](#4-mensagens)
5. [Grupos](#5-grupos)
6. [Canais públicos](#6-canais-publicos)
7. [Chamadas](#7-chamadas)
8. [Calendário](#8-calendario)
9. [Sondagens](#9-sondagens)
10. [Múltiplas identidades](#10-multiplas-identidades)
11. [Multidispositivo](#11-multidispositivo)
12. [Recuperação](#12-recuperacao)
13. [Configurações](#13-configuracoes)
14. [Segurança](#14-seguranca)
15. [Atualizações de software](#15-atualizacoes-de-software)
16. [Perguntas frequentes](#16-perguntas-frequentes)

---

## 1. O que é o Cleona Chat?

### O seu messenger, os seus dados

O Cleona Chat é um messenger que funciona completamente sem servidor central.
As suas mensagens vão diretamente do seu dispositivo para o dispositivo do
seu interlocutor -- sem passar por uma sede empresarial, sem nuvem, sem
centro de dados. Nenhuma empresa pode ler, armazenar ou repassar as suas
mensagens, porque simplesmente não existe nenhuma empresa pelo meio.

### Sem conta, sem número de telefone

No Cleona, não precisa de um número de telefone nem de um endereço de
e-mail para se registar. A sua identidade consiste num par de chaves
criptográficas, gerado automaticamente no seu dispositivo na primeira
utilização. Isso significa que ninguém pode localizá-lo através do seu
número de telefone ou endereço de e-mail, a menos que você próprio partilhe
os seus dados de contacto.

### Encriptação preparada para o futuro

O Cleona utiliza a chamada encriptação pós-quântica. Isto significa que
mesmo futuros computadores quânticos não conseguiriam decifrar as suas
mensagens. Não precisa de compreender os detalhes técnicos -- o importante
é que a sua comunicação está protegida da melhor forma possível, de acordo
com o estado atual da tecnologia.

### Como é que isto funciona sem servidor?

Imagine que você e os seus contactos formam juntos uma rede. Cada
dispositivo ajuda a encaminhar mensagens. Se o seu interlocutor estiver
online, a mensagem vai diretamente até ele. Se estiver offline, contactos
em comum guardam a mensagem temporariamente e entregam-na assim que o
destinatário voltar a estar disponível. Os seus contactos são, portanto,
também a sua rede.

### Plataformas

O Cleona está disponível para Android, iOS, macOS, Linux e Windows.

---

## 2. Primeiros passos

### Instalar a aplicação

**Android:**
1. Descarregue o ficheiro APK a partir do site do Cleona ou do GitHub Releases.
2. Abra o ficheiro no seu telemóvel. Se necessário, permita a instalação a
   partir de origens desconhecidas (o Android pergunta automaticamente).
3. Toque em "Instalar" e aguarde até a instalação estar concluída.

**iOS:**
1. Abra o link de convite do TestFlight no seu iPhone.
2. Toque em "Instalar". O TestFlight é a via oficial da Apple para
   distribuir aplicações beta.
3. Após a instalação, encontrará o Cleona no seu ecrã principal.

**macOS:**
1. Descarregue o ficheiro DMG a partir do site do Cleona ou do GitHub Releases.
2. Abra o DMG e arraste o Cleona para a sua pasta de Aplicações.
3. Na primeira utilização, o macOS poderá perguntar se deseja abrir a
   aplicação de um programador identificado -- confirme esta ação.

**Linux (Ubuntu/Debian):**
1. Descarregue o ficheiro .deb a partir do site do Cleona ou do GitHub Releases.
2. Instale com um duplo clique ou no terminal: `sudo dpkg -i cleona-chat_VERSION_amd64.deb`
3. Inicie o Cleona através do menu de aplicações ou no terminal com `cleona-chat`.

**Linux (Fedora/openSUSE):**
1. Descarregue o ficheiro .rpm a partir do site do Cleona ou do GitHub Releases.
2. Instale com: `sudo dnf install cleona-chat-VERSION.x86_64.rpm`
3. Inicie o Cleona através do menu de aplicações ou no terminal com `cleona-chat`.

**Linux (todas as distribuições -- AppImage):**
1. Descarregue o ficheiro .AppImage a partir do site do Cleona ou do GitHub Releases.
2. Torne o ficheiro executável: clique com o botão direito, Propriedades,
   Executável, ou no terminal: `chmod +x cleona-chat-VERSION-x86_64.AppImage`
3. Inicie com duplo clique ou no terminal: `./cleona-chat-VERSION-x86_64.AppImage`

**Windows:**
1. Descarregue o instalador a partir do site do Cleona ou do GitHub Releases.
2. Execute o ficheiro de instalação e siga as instruções.
3. Inicie o Cleona através do menu Iniciar ou do atalho no ambiente de trabalho.

### Criar identidade

Na primeira utilização, o Cleona cria automaticamente uma nova identidade
para si. Pode definir um nome de exibição -- é o nome que os seus contactos
verão. Este nome pode ser alterado a qualquer momento.

### Anotar a Seed-Phrase -- o mais importante de tudo

Depois de criar a sua identidade, o Cleona mostra-lhe 24 palavras. Esta é a
sua **Seed-Phrase** -- a sua chave pessoal de recuperação.

**Anote estas 24 palavras em papel e guarde-as num local seguro.**

Porque é que isto é tão importante?

- Se o seu telemóvel se avariar, se perder ou for roubado, pode utilizar
  estas 24 palavras para recuperar toda a sua identidade num novo
  dispositivo.
- Sem a Seed-Phrase não há caminho de volta. Não existe um botão de
  "esqueci-me da palavra-passe" nem um suporte técnico que lhe possa
  devolver a sua conta -- porque, simplesmente, não existe nenhuma conta
  num servidor.
- Nunca partilhe a Seed-Phrase com outras pessoas. Quem conhecer estas
  palavras pode fazer-se passar por si.

Mais tarde, também encontrará a Seed-Phrase nas configurações, em
"Segurança", caso precise de a consultar novamente.

### Adicionar o primeiro contacto

Para conversar com alguém, primeiro tem de adicionar essa pessoa como
contacto. Existem várias formas de o fazer -- todas explicadas na secção
seguinte.

---

## 3. Contactos

### Ler QR-Code (recomendado)

A forma mais simples de adicionar um contacto:

1. O seu interlocutor abre a sua página de detalhes de identidade (toque no
   seu próprio nome na barra superior) e mostra-lhe o seu QR-Code.
2. Você toca no botão de mais (+) e escolhe "Ler QR-Code".
3. Aponte o seu telemóvel para o QR-Code do seu interlocutor.
4. O pedido de contacto é enviado automaticamente. Assim que o seu
   interlocutor o aceitar, já podem conversar.

Quando se encontram pessoalmente, o QR-Code é o método mais seguro, porque
sabe exatamente com quem está a trocar o contacto.

### NFC (aproximar os telemóveis)

Se ambos os dispositivos suportarem NFC:

1. Ambos abrem a função de adicionar contacto.
2. Encostem os telemóveis costas com costas.
3. Os dados de contacto são trocados automaticamente.

Tal como o QR-Code, o NFC oferece um elevado nível de segurança, porque a
troca só funciona se estiverem fisicamente próximos um do outro.

### Partilhar link (URI cleona://)

Também pode enviar o seu link de contacto por e-mail, SMS ou através de
outro messenger:

1. Abra a sua página de detalhes de identidade.
2. Copie o seu link cleona://.
3. Envie o link à pessoa que o deve adicionar.
4. A outra pessoa abre o link, ou cola-o na caixa de diálogo de adicionar
   contacto.

Atenção: com este método, está a confiar que o link não foi alterado
durante a transmissão. Para contactos especialmente sensíveis,
recomendamos o QR-Code ou o NFC.

### Aceitar pedidos de contacto

Quando alguém lhe envia um pedido de contacto, este aparece na sua caixa de
entrada (o último separador na barra inferior). Aí pode:

- **Aceitar** -- a pessoa é adicionada aos seus contactos.
- **Recusar** -- o pedido é descartado.
- **Bloquear** -- a pessoa deixa de poder enviar-lhe novos pedidos.

### Níveis de verificação

O Cleona mostra-lhe o quão seguramente confirmada está a identidade de um
contacto:

| Nível | Significado |
|-------|-----------|
| Desconhecido | Recebeu apenas o Node-ID ou um link. |
| Visto | A troca de chaves foi bem-sucedida, já podem comunicar de forma encriptada. |
| Verificado | Encontraram-se pessoalmente e verificaram-se por QR-Code ou NFC. |
| Confiável | Marcou explicitamente este contacto como confiável. |

Quanto mais alto o nível, mais seguro pode estar de que está realmente a
falar com a pessoa certa.

---

## 4. Mensagens

### Enviar e receber texto

Basta escrever a sua mensagem na caixa de texto em baixo e premir Enter ou
o botão de enviar. A sua mensagem é automaticamente encriptada antes de sair
do seu dispositivo.

As mensagens recebidas aparecem no histórico da conversa. Um visto (check)
mostra-lhe se a sua mensagem foi entregue.

### Enviar imagens, vídeos e ficheiros

Tem várias opções:

- **Ícone de clipe** na caixa de texto: toque nele para escolher um
  ficheiro, uma imagem ou um vídeo da sua galeria ou do sistema de
  ficheiros.
- **Arrastar e largar** (Desktop): arraste um ficheiro diretamente para a
  janela do chat.
- **Colar da área de transferência** (Desktop): copie uma imagem e cole-a
  no chat.

Ficheiros pequenos (menos de 256 KB) são enviados diretamente. Ficheiros
maiores são transferidos num processo em duas fases: primeiro a
transferência é anunciada, depois transmitida em partes.

### Mensagens de voz

1. Mantenha premido o botão do microfone na caixa de texto.
2. Diga a sua mensagem.
3. Solte o botão para enviar a mensagem.

Se o reconhecimento de voz estiver ativado no seu dispositivo (ver
configurações), a sua mensagem de voz é automaticamente transcrita para
texto. O seu interlocutor vê então tanto a gravação como o texto
transcrito.

### Responder a mensagens (citação)

Para responder a uma mensagem específica:

1. Abra o menu de três pontos junto à mensagem.
2. Escolha "Responder".
3. Aparece uma faixa por cima da caixa de texto com a mensagem citada.
4. Escreva a sua resposta e envie-a.

A mensagem citada é apresentada na sua resposta, para que a referência
fique clara.

### Editar e eliminar mensagens

- **Editar:** menu de três pontos da mensagem, depois "Editar". Altere o
  texto e envie-o novamente. O seu interlocutor vê que a mensagem foi
  editada. A edição é possível até 15 minutos após o envio.
- **Eliminar:** menu de três pontos da mensagem, depois "Eliminar". A
  mensagem é removida tanto do seu lado como do lado do seu interlocutor.
  Pode eliminar as suas próprias mensagens a qualquer momento -- não existe
  janela temporal para a eliminação.

### Reações com emoji

Em vez de escrever uma resposta, pode reagir a uma mensagem com um emoji:

1. Abra o menu de três pontos ou mantenha a mensagem premida.
2. Escolha um emoji na seleção rápida ou abra o seletor de emojis para ver
   todas as opções.
3. A sua reação aparece por baixo da mensagem.

### Copiar texto

Através do menu de três pontos de uma mensagem, pode copiar o texto da
mensagem para a área de transferência.

### Pesquisar mensagens

Na parte superior da janela do chat encontra a função de pesquisa. Digite
um termo de pesquisa e o Cleona mostra-lhe todos os resultados na conversa
atual. Com as teclas de seta pode saltar entre os resultados.

No ecrã inicial existe ainda um filtro de pesquisa entre separadores, com o
qual pode pesquisar todas as conversas por um termo.

### Pré-visualização de links

Quando envia um link, o Cleona gera automaticamente uma pré-visualização
(título, descrição, imagem de pré-visualização). Esta pré-visualização é
criada pelo seu dispositivo e enviada junto com a mensagem -- o seu
interlocutor não precisa de estabelecer nenhuma ligação ao site associado
ao link.

Quando toca num link recebido, é-lhe perguntado se deseja abri-lo no
navegador normal, em modo anónimo, ou não o abrir de todo.

---

## 5. Grupos

### Criar um grupo

1. Mude para o separador "Grupos".
2. Toque no botão de mais (+).
3. Dê um nome ao grupo.
4. Escolha os contactos que deseja convidar.
5. Toque em "Criar".

Os contactos convidados recebem uma notificação e podem juntar-se ao grupo.

### Convidar membros

Mesmo depois da criação, pode convidar mais contactos:

1. Abra as informações do grupo (menu de três pontos na vista geral do
   grupo ou barra superior no chat de grupo).
2. Toque em "Convidar".
3. Escolha os contactos que deseja adicionar.

### Funções

Cada grupo tem três funções:

- **Proprietário (Owner):** Tem controlo total. Pode adicionar e remover
  membros, nomear administradores e gerir o grupo. O proprietário também
  pode transferir o seu estatuto para outro membro.
- **Administrador:** Pode remover membros e ajudar na gestão.
- **Membro:** Pode ler e escrever mensagens.

### Sair de um grupo

1. Abra o menu de três pontos na vista geral do grupo.
2. Escolha "Sair".
3. Confirme a sua decisão.

Quando sai de um grupo, as suas mensagens anteriores permanecem visíveis
para os outros membros.

---

## 6. Canais públicos

### O que são canais?

Os canais são fóruns de discussão públicos dentro da rede Cleona. Ao
contrário dos grupos, aqui qualquer pessoa pode ler sem precisar de ser
convidada. Apenas o proprietário e os administradores podem publicar
conteúdos -- os subscritores apenas leem.

### Encontrar e subscrever canais

1. Mude para o separador "Canais".
2. Abra o separador "Pesquisar".
3. Pesquise os canais disponíveis por nome ou tema.
4. Toque num canal e depois em "Subscrever".

Os canais podem ser filtrados por idioma. Alguns canais estão marcados
como "Conteúdo adulto" -- só ficam visíveis se tiver confirmado no seu
perfil que tem mais de 18 anos.

### Criar o seu próprio canal

1. Mude para o separador "Canais".
2. Toque no botão de mais (+).
3. Introduza um nome para o canal (tem de ser único em toda a rede).
4. Escolha o idioma e se o canal deve ser público ou privado.
5. Opcional: adicione uma descrição e uma imagem.
6. Toque em "Criar".

Nos canais públicos, pode definir se o conteúdo é classificado como
"Conteúdo adulto".

### Denunciar conteúdos

Se encontrar conteúdo inadequado num canal público, pode denunciá-lo. O
Cleona utiliza um sistema de moderação descentralizado: as denúncias são
avaliadas por membros da rede escolhidos aleatoriamente (uma espécie de
"júri popular"). Se for detetada uma infração, o canal recebe um aviso. Em
caso de infrações repetidas, o canal é despromovido no índice de pesquisa
ou bloqueado.

### Canais de sistema

O Cleona dispõe de dois canais de sistema incorporados:

- **Bug Log:** Quando o Cleona deteta um erro, pergunta-lhe se deseja
  enviar um relatório de erro anonimizado. Estes relatórios são publicados
  no canal Bug Log, onde podem ser consultados pela comunidade. Não são
  transmitidos dados pessoais -- apenas descrições técnicas do erro. Também
  pode enviar manualmente um relatório de registo (com diálogo de
  pré-visualização e consentimento explícito).
- **Feature Requests:** Aqui os usuários podem submeter pedidos de
  funcionalidades e votar em propostas já existentes. As propostas são
  ordenadas por número de votos.

Ambos os canais de sistema têm um limite de tamanho de 25 MB e são
supervisionados pelo sistema de moderação por júri.

---

## 7. Chamadas

### Iniciar uma chamada de voz

1. Abra o chat com o contacto que deseja chamar.
2. Toque no ícone de telefone na barra superior.
3. Aguarde até o seu interlocutor atender a chamada.

Durante a conversa, vê um cronómetro com a duração da chamada e tem acesso
a silenciar o microfone e ao altifalante.

Para desligar, toque no botão vermelho de desligar.

### Iniciar uma videochamada

1. Abra o chat com o contacto.
2. Toque no ícone de câmara na barra superior.
3. A sua imagem de vídeo aparece numa janela pequena, e a imagem do seu
   interlocutor na área grande.

Durante a chamada, pode alternar entre a câmara frontal e a traseira.

### Chamadas recebidas

Quando alguém lhe liga, aparece uma janela de notificação com o nome de
quem chama. Pode:

- **Atender** -- a chamada começa.
- **Recusar** -- quem chama é notificado.

Se já estiver numa chamada, uma nova chamada é automaticamente recusada.

### Chamadas em grupo

Também pode fazer chamadas em grupo, com várias pessoas a participar em
simultâneo. A chamada é organizada através de uma árvore de encaminhamento
inteligente, de forma que nem todos os participantes precisam de estar
diretamente ligados uns aos outros. Todas as conversas são encriptadas de
ponta a ponta.

### Encriptação nas chamadas

Todas as chamadas são encriptadas com chaves únicas, que existem apenas
durante a duração da conversa. Depois de desligar, estas chaves são
imediatamente eliminadas. Ninguém pode decifrar posteriormente uma
conversa passada.

---

## 8. Calendário

O Cleona inclui um calendário incorporado, que funciona de forma
encriptada e completamente descentralizada -- sem serviço na nuvem.

### Vistas

O calendário oferece cinco vistas: Dia, Semana, Mês, Ano e uma vista de
Tarefas. Alterne entre elas através dos separadores na parte superior do
ecrã do calendário.

### Criar eventos

Toque num intervalo de tempo ou utilize o botão de adicionar para criar um
novo evento. Pode introduzir título, data, hora, local e notas. Os eventos
são guardados de forma encriptada no seu dispositivo.

### Eventos recorrentes

Os eventos podem repetir-se diariamente, semanalmente, mensalmente ou
anualmente. Pode ajustar o padrão (por exemplo, de duas em duas
terças-feiras, ou no primeiro dia de cada mês) e definir uma data de
término ou um número de repetições.

### Convidar contactos

Ao criar ou editar um evento, pode convidar os seus contactos do Cleona.
Eles recebem um convite de calendário encriptado e podem responder com
Aceito, Recuso ou Talvez. As alterações ao evento são enviadas
automaticamente a todos os convidados.

### Indicação de disponibilidade (Livre/Ocupado)

Pode partilhar a sua disponibilidade com contactos sem revelar os detalhes
dos eventos. Existem três níveis de privacidade: detalhes completos, apenas
blocos de tempo, ou oculto. Pode definir uma predefinição e substituí-la
por contacto.

### Lembretes

Os eventos podem ter lembretes, que disparam uma notificação do sistema
antes do início do evento. Pode adiar os lembretes conforme necessário.

### Sincronização com calendário externo

O Cleona pode sincronizar-se com serviços de calendário externos:

- **CalDAV** -- Ligue-se a qualquer servidor compatível com CalDAV
  (Nextcloud, Radicale, etc.).
- **Google Calendar** -- Sincronização através da Google Calendar API com
  autenticação segura via OAuth2.
- **Servidor CalDAV local** -- O Cleona pode iniciar um servidor CalDAV
  local no seu dispositivo, para que aplicações de calendário de ambiente
  de trabalho (Thunderbird, Outlook, Apple Calendar, Evolution) possam
  sincronizar com o seu calendário Cleona.
- **Calendário do sistema Android** -- Os eventos do Cleona podem ser
  transferidos para a aplicação de calendário incorporada no seu
  dispositivo Android.
- **Ficheiros ICS** -- Importe e exporte eventos no formato padrão
  iCalendar.

### Exportação em PDF

Pode imprimir ou exportar qualquer vista do calendário (Dia, Semana, Mês,
Ano) como documento PDF.

---

## 9. Sondagens

Pode criar sondagens em qualquer chat ou grupo, para recolher opiniões ou
planear datas.

### Tipos de sondagem

O Cleona suporta cinco tipos de sondagem:

- **Escolha única** -- os participantes escolhem uma opção.
- **Escolha múltipla** -- os participantes podem escolher várias opções.
- **Sondagem de data** -- encontre uma data que sirva a todos. Cada
  participante marca as datas como disponível, talvez ou indisponível.
- **Escala** -- avalie algo numa escala numérica (por exemplo, de 1 a 5).
- **Texto livre** -- os participantes escrevem a sua própria resposta.

### Criar uma sondagem

Abra um chat e toque no ícone de sondagem (ou utilize o menu de anexos).
Escolha o tipo de sondagem, formule a sua pergunta e as opções, e envie a
sondagem. Ela aparece como uma mensagem no chat.

### Votar

Toque numa sondagem para dar o seu voto. Pode alterar ou retirar o seu
voto a qualquer momento.

### Votação anónima

As sondagens podem ser configuradas para votação anónima. Quando ativada,
os votos são criptograficamente anónimos -- ninguém, nem mesmo o criador
da sondagem, pode ver quem votou em quê. O número de votos continua
visível.

### Sondagem de data para o calendário

Quando uma sondagem de data é concluída, a data vencedora pode ser
convertida diretamente num evento de calendário com um toque.

---

## 10. Múltiplas identidades

### Porquê várias identidades?

Imagine que deseja separar a sua vida profissional da sua vida pessoal --
algo semelhante a ter dois números de telefone diferentes, mas sem um
segundo telemóvel. No Cleona, pode utilizar várias identidades num único
dispositivo. Cada identidade tem o seu próprio nome, a sua própria imagem
de perfil, os seus próprios contactos e as suas próprias conversas.

### Criar uma nova identidade

1. Na barra superior, vê a sua identidade atual como um separador.
2. Toque no sinal de mais (+) à direita dos seus separadores de
   identidade.
3. Introduza um nome para a nova identidade.
4. Pronto -- a nova identidade fica ativa de imediato.

### Alternar entre identidades

Basta tocar no separador de identidade na barra superior. A troca é
imediata -- sem tempo de espera, sem recarregamento.

### Todas funcionam em simultâneo

Um ponto importante: todas as suas identidades estão ativas ao mesmo
tempo. Mesmo que esteja a ser exibido como "Profissional", a sua
identidade "Pessoal" continua a receber mensagens. Não perde nada,
independentemente da identidade que tenha selecionada no momento.

### Página de detalhes da identidade

Ao tocar no separador da sua identidade atualmente ativa, abre-se a página
de detalhes. Aqui pode:

- Mostrar o seu QR-Code para contactos.
- Alterar ou remover a sua imagem de perfil.
- Adicionar uma descrição de perfil.
- Alterar o seu nome de exibição.
- Escolher um design (Skin) para esta identidade.
- Eliminar a identidade, caso já não precise dela.

### Eliminar uma identidade

Ao eliminar uma identidade, os seus contactos são notificados. A
identidade e todos os dados associados são removidos do seu dispositivo.
Este processo não é reversível.

---

## 11. Multidispositivo

### Utilizar o Cleona em vários dispositivos

Pode utilizar a mesma identidade em até 5 dispositivos simultaneamente. Um
dispositivo é o principal (guarda a Seed-Phrase), e outros dispositivos
são associados a este.

### Associar um novo dispositivo

1. Abra as configurações no seu dispositivo principal.
2. Vá a "Dispositivos associados".
3. Escolha "Associar novo dispositivo".
4. Instale o Cleona no novo dispositivo e, no arranque, escolha "Associar a
   dispositivo existente".
5. Leia o código QR de emparelhamento exibido no seu dispositivo principal,
   ou utilize o link de emparelhamento.

O dispositivo associado recebe um certificado de delegação do dispositivo
principal. As mensagens enviadas a partir de um dispositivo associado são
assinadas criptograficamente com uma chave delegada, para que os contactos
possam verificar que a mensagem provém realmente da sua identidade.

### Como funciona

- O dispositivo principal guarda a sua Seed-Phrase e as chaves-mestre.
- Os dispositivos associados recebem chaves de assinatura derivadas e um
  certificado de delegação -- nunca recebem a Seed-Phrase em si.
- Todos os dispositivos partilham a mesma identidade e os mesmos
  contactos. As mensagens chegam a todos os dispositivos.
- Os certificados de delegação são renovados automaticamente antes de
  expirarem.

### Gestão de dispositivos

Abra as configurações e vá a "Dispositivos associados" para ver todos os
seus dispositivos associados, o respetivo estado e a última atividade.
Pode revogar um dispositivo associado a qualquer momento, caso se perca ou
seja roubado.

### Rotação de chaves de emergência

Se suspeitar que um dispositivo foi comprometido, pode acionar uma
rotação de chaves de emergência. Nesse processo, são geradas novas chaves,
e a rotação tem de ser confirmada por uma maioria dos seus outros
dispositivos. Isto impede que um único dispositivo roubado possa rodar as
chaves por conta própria.

---

## 12. Recuperação

### Utilizar a Seed-Phrase

Se perder o seu dispositivo ou configurar um novo:

1. Instale o Cleona no novo dispositivo.
2. No arranque, escolha "Recuperar".
3. Introduza as suas 24 palavras.
4. O Cleona restaura a sua identidade e contacta automaticamente os seus
   contactos anteriores.
5. Os seus contactos respondem com os seus dados de contacto, associações
   a grupos e históricos de mensagens.

A recuperação acontece em três etapas:
- Primeiro voltam os seus contactos e grupos.
- Depois, as últimas 50 mensagens de cada conversa.
- Por fim, o histórico completo de mensagens.

Basta que um único dos seus contactos esteja online para que a
recuperação funcione.

### Guardian Recovery (pessoas de confiança)

Pode nomear até cinco pessoas de confiança como "Guardians". Nesse
processo, a sua chave de recuperação é dividida em cinco partes, cada uma
das quais é entregue a um Guardian. Para recuperar a sua identidade,
bastam três das cinco partes.

Isto significa que, mesmo que tenha perdido a sua Seed-Phrase, três dos
seus Guardians podem, em conjunto, recuperar a sua conta. Nenhum Guardian
individual pode, sozinho, aceder aos seus dados -- são sempre necessários
pelo menos três.

Assim configura os Guardians:
1. Abra as configurações.
2. Vá a "Segurança".
3. Escolha "Guardian Recovery".
4. Escolha cinco contactos de confiança.

### Porque é que os contactos são o seu backup

Nos messengers tradicionais, os seus dados ficam nos servidores do
fornecedor. No Cleona não há servidor -- mas os seus contactos assumem
esse papel. Quando envia uma mensagem, contactos em comum guardam uma
cópia encriptada, para o caso de o destinatário estar offline no momento.
Numa recuperação, são os seus contactos que lhe devolvem os seus dados.

Isto significa que, quantos mais contactos ativos tiver, mais fiável é o
seu backup. Um único contacto que esteja regularmente online já é
suficiente para uma recuperação bem-sucedida.

---

## 13. Configurações

Pode aceder às configurações através do ícone de roda dentada no canto
superior direito.

### Notificações e toques

- Escolha entre seis toques diferentes para chamadas recebidas.
- Defina um som de notificação para mensagens.
- Em dispositivos Android, pode ainda ativar ou desativar a vibração.

### Designs (Skins)

O Cleona oferece dez designs diferentes: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold e Contrast. O design Contrast cumpre o
nível mais elevado de acessibilidade (WCAG AAA) e é especialmente legível
para pessoas com visão reduzida.

Cada identidade pode ter o seu próprio design. Altere o design na página
de detalhes da identidade (toque no separador de identidade ativo).

Adicionalmente, nas configurações, em "Aparência", pode alternar entre o
tema claro, o tema escuro e o tema do sistema.

### Alterar o idioma

O Cleona está disponível em 33 idiomas, incluindo idiomas escritos da
direita para a esquerda (por exemplo, árabe, hebraico). Altere o idioma
nas configurações, em "Idioma".

### Limite de armazenamento

Pode definir quanto espaço de armazenamento o Cleona pode utilizar no seu
dispositivo (entre 100 MB e 2 GB). Quando o limite é atingido, os media
mais antigos são automaticamente descarregados ou eliminados -- as
mensagens de texto são sempre preservadas.

### Arquivo de media

Se tiver um armazenamento em rede (NAS) ou uma pasta partilhada em casa, o
Cleona pode arquivar automaticamente os seus media para lá. São suportados
SMB, SFTP, FTPS e WebDAV.

Assim funciona o armazenamento em níveis:
- Nos primeiros 30 dias: tudo permanece no seu dispositivo.
- Após 30 dias: uma imagem de pré-visualização permanece no dispositivo, o
  original é arquivado.
- Após 90 dias: apenas permanece uma pequena imagem de pré-visualização no
  dispositivo.
- Após um ano: apenas permanece um marcador de posição, o original fica
  guardado com segurança no arquivo.

Pode tocar num media arquivado a qualquer momento para o recuperar --
desde que esteja ligado à sua rede doméstica. Os media particularmente
importantes podem ser fixados, para que nunca sejam arquivados.

### Transcrição de mensagens de voz

Quando ativada, as suas mensagens de voz são convertidas em texto
localmente, no seu dispositivo (com o modelo de código aberto Whisper). O
texto transcrito é enviado ao seu interlocutor junto com a gravação. A
transcrição acontece inteiramente no seu dispositivo -- nenhum dado é
enviado a serviços externos.

### Descarregamento automático

Pode definir a partir de que tamanho os media devem ser descarregados
automaticamente. Assim, por exemplo, pode deixar carregar imagens
automaticamente, mas decidir manualmente no caso de vídeos grandes.

### Dispositivos associados

Faça a gestão dos seus dispositivos associados nesta área das
configurações. Consulte o capítulo Multidispositivo para mais detalhes.

---

## 14. Segurança

### O que significa encriptação pós-quântica?

A encriptação atual baseia-se em problemas matemáticos que são
extremamente difíceis de resolver para computadores normais. Os
computadores quânticos poderão, no futuro, resolver rapidamente alguns
destes problemas. A encriptação pós-quântica utiliza métodos adicionais
que resistem também aos computadores quânticos.

O Cleona combina ambas as abordagens: encriptação clássica para
fiabilidade e métodos pós-quânticos para segurança a longo prazo. Assim,
está protegido simultaneamente contra ameaças atuais e futuras.

Para cada mensagem individual é gerada uma chave própria. Mesmo que um
atacante conseguisse decifrar a chave de uma mensagem, não conseguiria
com isso ler nenhuma outra mensagem.

### Porque é que a ausência de servidor é mais segura

Nos messengers tradicionais, as suas mensagens passam pelos servidores do
fornecedor. Mesmo que estejam encriptadas nesses servidores, o fornecedor
tem acesso a metadados (quem comunica com quem, quando, com que frequência
e de onde) e, em determinadas circunstâncias, tem de os entregar por
ordem judicial.

No Cleona não existe esse ponto central. As suas mensagens viajam
diretamente de dispositivo para dispositivo. Não há nenhum lugar onde
todos os metadados se concentrem. Ninguém pode reconstruir o seu
comportamento de comunicação a partir de um único ponto de dados.

### O que acontece quando você está offline?

Quando envia uma mensagem e o destinatário está offline:

1. O Cleona tenta primeiro entregar a mensagem diretamente.
2. Se isso não for possível, ela é encaminhada através de contactos em
   comum.
3. Ao mesmo tempo, a mensagem é dividida em fragmentos encriptados e
   distribuída por vários nós da rede (semelhante a um puzzle composto por
   10 peças, das quais 7 são suficientes para reconstituir a imagem).
4. A mensagem é conservada durante até 7 dias.

Assim que o destinatário volta a ficar online, as mensagens são
entregues. Recebe uma confirmação quando a sua mensagem chega ao destino.

### Anticensura

Se a sua rede bloquear o método de ligação padrão (UDP), o Cleona muda
automaticamente para uma transmissão alternativa (TLS), mais difícil de
detetar e de bloquear. Isto acontece de forma transparente -- não precisa
de configurar nada.

### Armazenamento seguro de chaves

Nas plataformas suportadas, o Cleona guarda as suas chaves de encriptação
no chaveiro seguro do sistema operativo (Android Keystore, iOS Keychain,
macOS Keychain). Onde disponível, isto oferece proteção com suporte de
hardware para as suas chaves.

### Encriptação da base de dados

Todas as suas mensagens, contactos e configurações são guardados de forma
encriptada no seu dispositivo. Mesmo que alguém obtivesse acesso ao seu
sistema de ficheiros, não conseguiria ler nada sem a sua chave
criptográfica. Esta chave é derivada da sua identidade e existe apenas no
seu dispositivo.

### Rede fechada

O Cleona funciona como uma rede fechada. Cada pacote de rede é
autenticado, de forma que apenas dispositivos Cleona legítimos podem
participar. Isto impede que pessoas externas injetem mensagens falsificadas
ou intercetem o tráfego de rede.

---

## 15. Atualizações de software

### Como recebo atualizações?

O Cleona pode ser atualizado de várias formas. O objetivo é que consiga
receber atualizações mesmo que determinados canais de distribuição
falhem ou sejam bloqueados:

1. **App Store / Play Store:** Se instalou o Cleona através de uma loja
   de aplicações, recebe atualizações da forma habitual, através da loja.
2. **GitHub Releases:** Na página do GitHub do projeto encontra pacotes de
   instalação assinados para todas as plataformas.
3. **Atualizações na rede (In-Network):** Se outro usuário do Cleona na
   sua rede já tiver a versão mais recente, o Cleona pode obter a
   atualização diretamente através da rede P2P -- sem servidor externo.
   Nesse processo, a nova versão é dividida em fragmentos com correção de
   erros e distribuída por vários nós. O seu dispositivo recolhe
   fragmentos suficientes e reconstitui a atualização. A autenticidade é
   verificada através de uma assinatura Ed25519 do programador.
4. **Links de convite:** Pode criar links de convite que contêm tudo o que
   um novo usuário precisa para instalar o Cleona e ligar-se à rede.
5. **Transferência física:** Em ambientes sem internet, pode partilhar o
   Cleona com outras pessoas através de uma pen USB ou na rede local.

### Notificação de atualização

Quando uma nova atualização está disponível, o Cleona mostra-lhe uma
notificação no ecrã inicial. Se a atualização também estiver disponível
através da rede (atualização In-Network), tem a opção de a descarregar
diretamente a partir da rede.

### Distribuição binária

Por predefinição, o seu dispositivo ajuda a distribuir atualizações a
outros usuários da rede. Se não quiser isto, pode desativar esta função
nas configurações, em "Rede". A utilização de armazenamento para
fragmentos de atualização é limitada (5 MB em dispositivos móveis, 20 MB
em dispositivos de secretária) e é limpa regularmente.

### Verificação de assinatura

Cada atualização é assinada criptograficamente. O Cleona verifica a
assinatura automaticamente antes de instalar qualquer atualização. Isto
garante que apenas são aceites atualizações do programador oficial --
mesmo que a atualização tenha sido obtida através da rede P2P.

---

## 16. Perguntas frequentes

### "Posso utilizar o Cleona sem internet?"

Não, o Cleona precisa de uma ligação de rede para enviar e receber
mensagens. No entanto, não precisa de estar online ao mesmo tempo que o
seu interlocutor: as mensagens enviadas enquanto o destinatário está
offline são guardadas temporariamente e entregues automaticamente assim
que ambos os lados voltarem a estar ligados. Na rede local (por exemplo,
na mesma rede WLAN), também podem comunicar entre si sem qualquer acesso à
internet.

### "E se eu perder a minha Seed-Phrase?"

Se tiver configurado Guardians, três das cinco pessoas de confiança podem,
em conjunto, restaurar o seu acesso. Sem Guardians e sem Seed-Phrase,
infelizmente não há forma de recuperar a sua identidade. Por isso é tão
importante guardar as 24 palavras em segurança.

### "Alguém pode ler as minhas mensagens?"

Não. Cada mensagem é encriptada com uma chave única, válida apenas para
essa mensagem. Só você e o seu interlocutor podem decifrar a mensagem.
Não existe nenhum servidor central, nenhuma chave-mestre e nenhum acesso
para o programador. Mesmo que um dispositivo encaminhe a mensagem no
percurso de transporte, só vê dados encriptados ilegíveis.

### "Porque é que não preciso de um número de telefone?"

Porque a sua identidade é puramente criptográfica. Em vez de um número de
telefone ou endereço de e-mail associado ao seu nome real, é um par de
chaves gerado no seu dispositivo que o identifica. Os contactos são
adicionados por QR-Code, NFC ou link -- não através de uma lista
telefónica. Isto significa mais privacidade, porque a sua conta de
messenger não está associada à sua identidade real.

### "Como é que encontro pessoas no Cleona?"

O Cleona não tem, propositadamente, uma pesquisa de contactos por número
de telefone ou nome -- isso seria um problema de privacidade. Em vez disso,
troca os dados de contacto diretamente: por QR-Code, NFC, link cleona://
ou em canais públicos. É como trocar cartões de visita, em vez de
consultar uma lista telefónica.

### "O Cleona funciona também no estrangeiro?"

Sim. Desde que tenha uma ligação à internet, o Cleona funciona em
qualquer lugar do mundo. Como não existe nenhum servidor central, o
serviço também não pode ser bloqueado para determinados países. O Cleona
dispõe ainda de um mecanismo de reserva anticensura: se a ligação normal
(UDP) for bloqueada, o Cleona muda automaticamente para uma transmissão
alternativa (TLS), mais difícil de detetar e de bloquear.

### "O Cleona é gratuito?"

Sim. O Cleona pode ser utilizado gratuitamente e sem publicidade. Como não
existe nenhum servidor central, também não há custos de servidor para a
operação. Na aplicação, em "Doação", encontra a possibilidade de apoiar
voluntariamente o desenvolvimento.

### "A minha mensagem tem um símbolo de relógio -- o que significa isso?"

Significa que a mensagem ainda não foi entregue. É provável que o seu
interlocutor esteja offline no momento. Assim que a mensagem for entregue,
o símbolo muda. As mensagens são conservadas até 7 dias para efeitos de
entrega.

### "Posso mudar do WhatsApp para o Cleona?"

Sim, mas não pode transferir as suas conversas do WhatsApp. O Cleona e o
WhatsApp são sistemas fundamentalmente diferentes. Tem de adicionar os
seus contactos um a um no Cleona. A forma mais simples é publicar o seu
link cleona:// num grupo de WhatsApp e pedir aos outros que o adicionem
por aí.

### "Posso utilizar o Cleona em vários dispositivos ao mesmo tempo?"

Sim. Pode associar até 5 dispositivos com a mesma identidade. Um
dispositivo é o principal (guarda a Seed-Phrase), e outros dispositivos
são associados através de um processo de emparelhamento seguro. Todos os
dispositivos partilham a mesma identidade, os mesmos contactos e as
mesmas conversas. Consulte o capítulo Multidispositivo para mais
detalhes.

### "Como recebo atualizações se a App Store estiver bloqueada?"

O Cleona pode obter atualizações diretamente através da rede P2P, sem
depender de uma App Store, de um site ou de um servidor de descarregamento.
Se outro usuário na rede tiver a versão mais recente, o seu dispositivo
pode carregar a atualização a partir daí. A autenticidade é verificada
através de uma assinatura digital do programador. Em alternativa, um
contacto pode partilhar a aplicação consigo através de um link de convite
ou de uma pen USB. Mais informações no capítulo "Atualizações de
software".

---

## Ajuda e contacto

Se tiver dúvidas ou encontrar algum problema, encontrará informações
atualizadas no site do Cleona e no GitHub. Como o Cleona é um projeto
descentralizado, não existe um suporte ao cliente clássico -- mas sim uma
comunidade ativa que ajuda com todo o gosto.

---

*Este manual descreve o Cleona Chat versão 3.1.125. Algumas funcionalidades
podem mudar ou ser ampliadas em versões mais recentes.*
