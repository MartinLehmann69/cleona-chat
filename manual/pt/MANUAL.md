# Cleona Chat -- Manual do Usuário

Versão 4.2 | Atualizado em novembro de 2026

---

## Índice

1. [O que é o Cleona Chat?](#1-o-que-é-o-cleona-chat)
2. [Primeiros passos](#2-primeiros-passos)
3. [Contatos](#3-contatos)
4. [Mensagens](#4-mensagens)
5. [Grupos](#5-grupos)
6. [Canais públicos](#6-canais-públicos)
7. [Chamadas](#7-chamadas)
8. [Calendário](#8-calendário)
9. [Enquetes](#9-enquetes)
10. [Múltiplas identidades](#10-múltiplas-identidades)
11. [Vários aparelhos](#11-vários-aparelhos)
12. [Recuperação](#12-recuperação)
13. [Configurações](#13-configurações)
14. [Segurança](#14-segurança)
15. [Atualizações de software](#15-atualizações-de-software)
16. [Perguntas frequentes](#16-perguntas-frequentes)

---

## 1. O que é o Cleona Chat?

### Seu mensageiro, seus dados

O Cleona Chat é um mensageiro que funciona completamente sem servidor central.
Suas mensagens viajam do seu aparelho para o aparelho do seu interlocutor --
sem desvio por uma sede de empresa, sem nuvem, sem datacenter. Onde, no
caminho, outro aparelho ajudar, ele apenas repassa pacotes criptografados.
Nenhuma empresa pode ler, armazenar ou repassar suas mensagens, simplesmente
porque nenhuma empresa está no meio.

### Sem conta, sem número de telefone

No Cleona você não precisa de número de telefone nem de endereço de e-mail
para se cadastrar. Sua identidade consiste em um par de chaves criptográfico,
gerado automaticamente no seu aparelho no primeiro início. Isso significa:
ninguém consegue localizá-lo pelo seu número de telefone ou endereço de e-mail,
a menos que você mesmo repasse seus dados de contato.

### Criptografia à prova do futuro

O Cleona usa a chamada criptografia pós-quântica. Isso significa: mesmo
futuros computadores quânticos não conseguiriam quebrar suas mensagens. Você
não precisa entender os detalhes -- o importante é apenas que sua comunicação
esteja protegida da melhor forma possível segundo o estado da técnica atual.

### Como funciona sem servidor?

A rede do Cleona é formada apenas pelos aparelhos de seus usuários. Cada
aparelho é um nó, nenhum nó é mais importante que outro, e cada um conhece
apenas seus vizinhos. Quatro coisas tornam esta rede especial:

- **Nenhum ponto fixo.** No app não consta nenhum endereço de servidor, e a
  rede não depende de nenhum nó isolado. Não há nada que se possa desligar
  para desligar o Cleona.
- **Imediato.** Sua mensagem parte no momento em que você a envia. Ela não
  espera por nenhum ritmo nem por nada mais.
- **Disfarce paralelo.** Seu aparelho envia continuamente pequenos pacotes de
  cobertura, de modo que, de fora, não se percebe quando você realmente
  escreve. Nenhuma mensagem depende disso -- o disfarce apenas roda em paralelo.
- **Códigos em vez de nomes.** Quem repassa uma mensagem vê apenas um código,
  que muda todos os dias. No caso normal, nenhum deles conhece remetente e
  destinatário ao mesmo tempo; as exceções estão no capítulo 14.

**Três caminhos, todos ao mesmo tempo.** Quando você envia uma mensagem, o
Cleona não tenta um caminho após o outro, mas todos os adequados de uma vez.
Assim que seu interlocutor confirma o recebimento, os demais são interrompidos.

1. **Na mesma rede:** Se vocês estão na mesma rede Wi-Fi, a mensagem vai
   direto.
2. **Pelos vizinhos fixos:** Na internet, seu aparelho entrega a mensagem ao
   seu vizinho fixo. Ele a repassa aos vizinhos fixos do seu interlocutor (até
   três de uma vez), e um deles a entrega.
3. **Caixa de correio:** Se seu interlocutor está offline, o Cleona deixa a
   mensagem criptografada com três vizinhos. Ela permanece lá por até 7 dias.
   Quando seu interlocutor volta a ficar online, ele a recolhe.

**Como você entra na rede?** No app não consta nenhum endereço de servidor.
Sua entrada você obtém do seu primeiro contato: o convite dele contém os
endereços pelos quais seu aparelho encontra seus primeiros vizinhos. Na mesma
rede Wi-Fi, aparelhos com Cleona também se encontram sozinhos. A partir daí,
seu aparelho vai conhecendo outros com cada vizinho.

### Plataformas

Cleona está disponível para Android, iOS, macOS, Linux e Windows. Em
computadores e no Android, mensagens e chamadas chegam em segundos. No iPhone,
isso vale enquanto o app está aberto. Quando não está, o iOS só o acorda de
vez em quando e por pouco tempo; quando isso acontece, o iOS decide. Cleona
recolhe então tudo o que foi guardado para você e mostra uma notificação com
um número no ícone do app. Chamadas não alcançam um iPhone com o app fechado.
Isso é uma regra da Apple, e não um defeito de Cleona.

---

## 2. Primeiros passos

### Instalar o app

**Android:**
1. Baixe o arquivo APK do site do Cleona ou do GitHub Releases.
2. Abra o arquivo no seu celular. Se necessário, autorize a instalação a
   partir de fontes desconhecidas (o Android perguntará automaticamente).
3. Toque em "Instalar" e aguarde até a conclusão da instalação.

**iOS:**
1. Abra o link de convite do TestFlight no seu iPhone.
2. Toque em "Instalar". O TestFlight é o caminho oficial da Apple para
   distribuir apps em beta.
3. Após a instalação, você encontrará o Cleona na sua tela inicial.

**macOS:**
1. Baixe o arquivo DMG do site do Cleona ou do GitHub Releases.
2. Abra o DMG e arraste o Cleona para a sua pasta de Aplicativos.
3. No primeiro início, o macOS pode perguntar se você deseja abrir o app de um
   desenvolvedor identificado -- confirme.

**Linux (Ubuntu/Debian):**
1. Baixe o arquivo .deb do site do Cleona ou do GitHub Releases.
2. Instale com duplo clique ou no terminal: `sudo dpkg -i cleona-chat-beta_VERSION_amd64.deb`
3. Inicie o Cleona pelo menu de aplicativos ou no terminal com `cleona-chat-beta`.

**Linux (Fedora/openSUSE):**
1. Baixe o arquivo .rpm do site do Cleona ou do GitHub Releases.
2. Instale com: `sudo dnf install cleona-chat-beta-VERSION-1.x86_64.rpm`
3. Inicie o Cleona pelo menu de aplicativos ou no terminal com `cleona-chat-beta`.

**Linux (todas as distribuições -- AppImage):**
1. Baixe o arquivo .AppImage do site do Cleona ou do GitHub Releases.
2. Torne o arquivo executável: clique direito, propriedades, executável, ou no terminal: `chmod +x cleona-chat-beta-VERSION-x86_64.AppImage`
3. Inicie com duplo clique ou no terminal: `./cleona-chat-beta-VERSION-x86_64.AppImage`

Os nomes dos pacotes valem para a beta, que no momento é a única versão
publicada; eles se chamam `cleona-chat-beta`.

**Windows:**
1. Baixe o instalador do site do Cleona ou do GitHub Releases.
2. Execute o arquivo de instalação e siga as instruções.
3. Inicie o Cleona pelo menu Iniciar ou pelo atalho da área de trabalho.

### Criar identidade

No primeiro início, o Cleona cria automaticamente uma nova identidade para
você. Você pode dar a si mesmo um nome de exibição -- é o nome que seus
contatos verão. Esse nome pode ser alterado a qualquer momento.

### Anotar a frase-semente -- o mais importante de tudo

Após a criação da sua identidade, o Cleona lhe mostra 24 palavras. Essa é a
sua **frase-semente** -- sua chave de recuperação pessoal.

**Anote essas 24 palavras em papel e guarde-as em segurança.**

Por que isso é tão importante?

- Se seu celular quebrar, for perdido ou roubado, você poderá, com essas 24
  palavras, restaurar toda a sua identidade em um aparelho novo.
- Sem a frase-semente, não há como voltar. Não existe botão de "esqueci a
  senha" nem um suporte que possa devolver sua conta -- porque não existe
  conta em servidor algum. Mesmo seus contatos não conseguem restaurar sua
  identidade, por mais que sejam. Um segundo aparelho com a mesma identidade
  virá numa versão posterior (veja o capítulo 11).
- Nunca repasse a frase-semente a terceiros. Quem conhece essas palavras pode
  se passar por você.

Você encontra as 24 palavras mais tarde também nas configurações, em
"Backup" -> "Mostrar frase de recuperação", caso queira consultá-las
novamente. No Android, você confirma isso com o seu bloqueio de tela.

### Adicionar o primeiro contato

Para conversar com alguém, primeiro você precisa adicioná-la como contato.
Para isso há vários caminhos -- todos explicados na próxima seção.

---

## 3. Contatos

### Seu convite

Contatos no Cleona surgem apenas por meio de um convite. Seu convite está lá
desde o primeiro início -- mesmo sem internet e antes que seu aparelho tenha
encontrado um vizinho. Você o encontra na página de detalhes da sua
identidade (toque no seu próprio nome na barra superior).

O convite existe em duas formas, que contêm exatamente a mesma coisa:

- como **QR-Code**, quando seu interlocutor está ao seu lado, e
- como **linha de texto**, que você envia por e-mail, SMS ou por outro
  mensageiro.

O convite não contém nenhum número de telefone nem nome de um diretório. Ele
contém suas chaves públicas e os endereços pelos quais seu interlocutor
alcança você e seus vizinhos. Para alguém que acabou de instalar o Cleona, seu
convite é, portanto, também a entrada na rede.

### Escanear QR-Code (recomendado)

Quando vocês se encontram pessoalmente:

1. Você mostra o QR-Code do seu convite ao seu interlocutor.
2. Seu interlocutor toca no botão de mais, escolhe "Escanear QR-Code" e
   aponta a câmera para a sua tela. Isso também funciona com a webcam de um
   computador.
3. O pedido vai até você e é **aceito automaticamente** -- afinal, você
   mesmo acabou de mostrar o código.

Um QR-Code vale apenas uma vez: o primeiro pedido válido é aceito, depois o
convite está consumido. O QR-Code é o método mais seguro, porque assim vocês
sabem exatamente com quem estão trocando o contato.

### NFC (encostar os celulares)

Se ambos os aparelhos suportam NFC:

1. Abram ambos a função de adicionar contato.
2. Encostem seus celulares, costas com costas.
3. O convite é transferido e aceito automaticamente.

O NFC oferece, como o QR-Code, alta segurança, porque a troca só funciona
quando vocês estão fisicamente lado a lado.

### Enviar a linha de texto

Quando vocês não podem se encontrar:

1. Abra seu convite e copie a linha de texto.
2. Envie-a à pessoa que deve adicioná-lo -- por e-mail, SMS ou por outro
   mensageiro.
3. A outra pessoa cola a linha no Cleona, no diálogo de adicionar contato.
4. O pedido aparece em você sob **"Pedidos"**. Aqui **não** é aceito
   automaticamente: você decide, pois não pode saber quem mais leu a linha no
   caminho.

### Aceitar pedidos de contato

Um pedido recebido ainda não cria um contato. Ele lhe faz uma pergunta e
aparece na aba **"Pedidos"**. Ali você vê o nome e o nível de verificação e
pode escolher:

- **Aceitar** -- só agora a pessoa se torna seu contato.
- **Recusar** -- o pedido é descartado.
- **Bloquear** -- a pessoa não pode lhe enviar outros pedidos.

### Nunca usar como vizinho fixo

No menu de um contato você encontra o interruptor **"Nunca usar como vizinho
fixo"** (padrão: desligado). Ligado, esse contato não repassa mensagens para
você e, por isso, também não fica sabendo quando você envia ou recebe
mensagens. Isso é pensado para o caso de uma ameaça vir do seu próprio
círculo.

De desconhecidos (nem contato nem membro de um grupo em comum), o Cleona
não deixa passar nada além desse tipo de pedido -- nenhuma mensagem, nenhuma
chamada, nenhum arquivo. E mesmo esse pedido só
chega se o remetente tiver resolvido antes uma pequena tarefa computacional.
Isso torna o spam em massa caro.

### Níveis de verificação

O Cleona indica quão seguramente a identidade de um contato está confirmada:

| Nível | Significado |
|-------|-------------|
| Não verificado | Vocês estão conectados, mas nada confirma que realmente a pessoa certa está por trás. |
| Visto | A troca de chaves foi bem-sucedida, vocês podem se comunicar de forma criptografada. |
| Verificado | Vocês se encontraram pessoalmente e se conectaram por scan de câmera ou NFC. |
| Confiável | Você marcou este contato expressamente como confiável. |

"Verificado" só existe para a troca pessoal. Um convite que veio por chat ou
por e-mail nunca atinge esse nível -- mesmo que contenha os mesmos dados.

Se as chaves de um contato mudam sem aviso, o Cleona o rebaixa para "Não
verificado". Isso o protege de alguém se passar, despercebido, pelo seu
contato.

---
## 4. Mensagens

### Enviar e receber texto

Basta digitar sua mensagem no campo de entrada, abaixo, e pressionar Enter ou
o botão de enviar. Sua mensagem é criptografada automaticamente antes de sair
do seu aparelho.

Mensagens recebidas aparecem no histórico do chat.

### O que os sinais na sua mensagem significam

| Sinal | Significado |
|---------|-------------|
| Relógio | A mensagem foi criada, mas ainda nenhum caminho a levou. |
| Um visto | A mensagem está a caminho. Isso também vale enquanto ela espera pelo seu interlocutor na caixa de correio. |
| Dois vistos | Entregue: o aparelho do seu interlocutor confirmou o recebimento. |
| Sinal de aviso | Por 14 dias, nenhum caminho levou a mensagem. Toque nela para reenviá-la. |

**Offline não é erro.** Se seu interlocutor não está alcançável, a mensagem
permanece com um visto até ser recolhida -- ela não está perdida. Se seu
próprio aparelho não tem conexão, a mensagem permanece no relógio e parte
sozinha assim que houver novamente um caminho. O sinal de aviso só aparece
quando ela ficou 14 dias sem encontrar nenhum caminho; então você pode
reenviá-la.

Isso também vale para um iPhone com o app fechado: a mensagem espera na caixa
de correio até o iOS acordar o app por um breve momento ou até que seu
interlocutor o abra. Isso pode demorar mais do que em outros dispositivos.

Dois vistos só existem quando o destinatário confirma o recebimento. Esse
recibo é criptografado e assinado -- ninguém no caminho pode falsificá-lo para
lhe simular uma entrega.

### Enviar imagens, vídeos e arquivos

Você tem várias opções:

- **Ícone de clipe de papel** no campo de entrada: toque nela para escolher um
  arquivo, uma imagem ou um vídeo da sua galeria ou do seu sistema de arquivos.
- **Arrastar e soltar** (desktop): arraste um arquivo para a janela do chat.
- **Colar da área de transferência** (desktop): copie uma imagem e cole-a no
  chat.

Arquivos pequenos (menos de 256 KB) viajam direto na mensagem. Arquivos
maiores são divididos em pedaços e recebem correção de erros, de modo que
pedaços individuais perdidos não fazem diferença. Se vocês dois estão online,
eles são transmitidos por um vizinho; caso contrário, são deixados em
aparelhos que estão sempre alcançáveis, até que seu interlocutor os recolha.

A partir de 256 KB, o Cleona lhe pergunta, por arquivo, antes de enviá-lo:
um arquivo grande não pode tomar o caminho das suas mensagens. Seu conteúdo
permanece criptografado, e seu interlocutor não fica sabendo o seu endereço de
internet. Mas a transferência é visível de fora como um evento, e um aparelho
de terceiros, que a repassa ou a guarda, vê quem envia e quem recolhe. A sua
aprovação vale apenas para esse único arquivo.

### Mensagens de voz

1. Mantenha pressionado o botão de microfone no campo de entrada.
2. Fale sua mensagem.
3. Solte o botão para enviar a mensagem.

Se o reconhecimento de voz está ativado no seu aparelho (veja configurações),
sua mensagem de voz é transcrita automaticamente para texto. Seu interlocutor
então vê tanto a gravação quanto o texto transcrito.

### Responder a mensagens (citar)

Para responder a uma mensagem específica:

1. Abra o menu de três pontos ao lado da mensagem.
2. Escolha "Responder".
3. Acima do campo de entrada aparece um banner com a mensagem citada.
4. Escreva sua resposta e envie-a.

A mensagem citada é exibida na sua resposta, de modo que a referência fica
clara.

### Editar e excluir mensagens

- **Editar:** menu de três pontos da mensagem, depois "Editar". Altere o texto
  e envie-o novamente. Seu interlocutor vê que a mensagem foi editada. A
  edição é possível dentro de 15 minutos após o envio.
- **Excluir:** menu de três pontos da mensagem, depois "Excluir". A mensagem
  é removida de você e do seu interlocutor. Você pode excluir suas próprias
  mensagens a qualquer momento -- não há janela de tempo para exclusão.

### Reações com emoji

Em vez de escrever uma resposta, você pode reagir a uma mensagem com um
emoji:

1. Abra o menu de três pontos ou mantenha a mensagem pressionada por um
   tempo.
2. Escolha um emoji da seleção rápida ou abra o seletor de emojis para a
   seleção completa.
3. Sua reação aparece abaixo da mensagem.

### Copiar texto

Pelo menu de três pontos de uma mensagem, você pode copiar o texto da mensagem
para a área de transferência.

### Pesquisar mensagens

Na parte superior da janela do chat você encontra a função de pesquisa.
Digite um termo de busca e o Cleona lhe mostra todas as ocorrências no chat
atual. Com as setas você pode alternar entre as ocorrências.

Na página inicial há, adicionalmente, um filtro de pesquisa entre abas, com o
qual você pode buscar todas as conversas por um termo.

### Pré-visualização de links

Quando você envia um link, o Cleona gera automaticamente uma pré-visualização
(título, descrição, imagem de pré-visualização). Essa pré-visualização é
criada no seu aparelho e enviada junto -- seu interlocutor não precisa, para
isso, estabelecer conexão com o site vinculado.

O que um toque em um link recebido faz, você define nas configurações, em
"Abrir links": "Normal", "Preferir janela anônima" (onde o aparelho não
consegue abrir uma janela anônima, o link abre normalmente) ou "Perguntar
sempre".

---

## 5. Grupos

### Criar grupo

1. Mude para a aba "Grupos".
2. Toque no botão de mais.
3. Dê um nome ao grupo.
4. Escolha os contatos que deseja convidar.
5. Toque em "Criar".

Os contatos convidados recebem uma notificação e podem entrar no grupo.

### Como as mensagens de grupo são protegidas

Em um grupo com até 16 membros, o Cleona envia cada mensagem a cada membro
individualmente -- cada uma criptografada apenas para esse membro, como se
você tivesse escrito a cada um uma mensagem própria. Os vistos em uma
mensagem de grupo mostram o estado do membro em que está menos avançada.

Se o grupo cresce para além de 16 membros, ele usa uma chave comum. Ela muda
todos os dias e é renovada quando um membro sai ou é removido; um novo membro
lê apenas a partir da sua entrada. Ali, os vistos não mostram mais o estado
de cada membro, mas que a mensagem está depositada na rede. Se o grupo cai
para 12 membros ou menos, ele volta ao envio individual.

### Imagens em grupos e canais

Nas configurações de um grupo ou de um canal, você define, com "Sempre
carregar imagens", se as imagens são carregadas imediatamente ou só quando
você toca em uma delas.

### Convidar membros

Mesmo após a criação, você pode convidar mais contatos:

1. Abra as informações do grupo (menu de três pontos na visão geral de
   grupos ou barra superior no chat do grupo).
2. Toque em "Convidar".
3. Escolha os contatos que deseja adicionar.

### Funções

Cada grupo tem três funções:

- **Proprietário (Owner):** Tem controle total. Pode adicionar e remover
  membros, nomear admins e gerenciar o grupo. O proprietário também pode
  transferir seu status a outro membro.
- **Admin:** Pode remover membros e ajudar na administração.
- **Membro:** Pode ler e escrever mensagens.

### Sair do grupo

1. Abra o menu de três pontos na visão geral de grupos.
2. Escolha "Sair".
3. Confirme sua decisão.

Quando você sai de um grupo, suas mensagens anteriores permanecem visíveis
para os demais membros.

---

## 6. Canais públicos

### O que são canais?

Canais são fóruns de discussão públicos dentro da rede do Cleona. Ao
contrário dos grupos, aqui qualquer um pode ler, sem precisar de convite.
Apenas o proprietário e admins podem publicar posts -- os assinantes leem.

### Encontrar canais e entrar

1. Mude para a aba "Canais".
2. Abra a aba "Busca".
3. Pesquise os canais disponíveis por nome ou tema.
4. Toque em um canal e depois em "Assinar".

Os canais podem ser filtrados por idioma. Alguns canais estão marcados como
"Não recomendado para menores" -- esses só ficam visíveis se você, no seu
perfil, tiver confirmado que tem mais de 18 anos.

### Criar seu próprio canal

1. Mude para a aba "Canais".
2. Toque no botão de mais.
3. Digite um nome de canal (deve ser único em toda a rede).
4. Escolha o idioma e se o canal deve ser público ou privado.
5. Opcional: adicione uma descrição e uma imagem.
6. Toque em "Criar".

Em canais públicos, você pode definir se o conteúdo é classificado como
"Não recomendado para menores".

### Denunciar conteúdos

Se você perceber conteúdos inadequados em um canal público, pode denunciá-los.
O Cleona usa um sistema de moderação descentralizado: as denúncias são
avaliadas por membros da rede escolhidos aleatoriamente (uma espécie de
"júri"). Se uma violação é constatada, o canal recebe um aviso. Em violações
repetidas, ele é rebaixado no índice de busca ou bloqueado.

### Canais do sistema

O Cleona dispõe de dois canais do sistema integrados:

- **Bug Log:** Quando o Cleona reconhece um erro, ele pergunta se você deseja
  enviar um relatório de erro; antes, você vê exatamente o que será
  publicado. Esses relatórios vão para o canal Bug Log, onde podem ser vistos
  pela comunidade. Um relatório não carrega nome nem conteúdo das suas
  conversas, e sim um pseudônimo. Na beta, ele indica adicionalmente a sua
  identificação (User-ID), para que os desenvolvedores possam perguntar. Você
  também pode enviar manualmente um relatório de log (com diálogo de
  pré-visualização e consentimento explícito).
- **Feature Requests:** Aqui os usuários podem enviar pedidos de
  funcionalidades e votar nas sugestões existentes. As sugestões são
  ordenadas por votos.

Cada computador guarda até 25 MB por canal do sistema, cada celular até
5 MB; quando isso enche, sai o mais antigo primeiro -- nunca o que você
mesmo já viu.

---
## 7. Chamadas

### Iniciar chamada de voz

1. Abra o chat com o contato que deseja chamar.
2. Toque no ícone de telefone na barra superior.
3. Aguarde até que seu interlocutor atenda a chamada.

Durante a conversa, você vê uma linha do tempo, a duração da conversa e tem
acesso a silenciar e alto-falante.

Para desligar, toque no botão vermelho de desligar.

Se você vê "Indisponível", o dispositivo do seu interlocutor não está
alcançável no momento, por exemplo um iPhone com o app fechado. Em vez disso,
escreva uma mensagem.

### Iniciar chamada de vídeo

1. Abra o chat com o contato.
2. Toque no ícone de câmera na barra superior.
3. Sua imagem de vídeo aparece em uma pequena janela, a imagem do seu
   interlocutor na área grande.

Você pode alternar entre a câmera frontal e a traseira durante a conversa.

### Chamadas recebidas

Quando alguém o chama, aparece uma janela de notificação com o nome do
chamador. Você pode:

- **Atender** -- a conversa começa.
- **Recusar** -- o chamador é notificado.

Se você está numa conversa no momento, uma nova chamada não toca; em vez
disso, você recebe uma mensagem "Chamada perdida". O mesmo vale para uma
chamada em grupo que você não atendeu -- a mensagem fica então no chat do
grupo.

Se alguém liga para uma das suas identidades que não está sendo exibida no
momento, o telefone toca mesmo assim; a tela de chamada indica qual das suas
identidades está sendo chamada.

No iPhone, o toque só acontece enquanto o app está aberto. Quem liga para você
enquanto o app está fechado vê "Indisponível" após 10 segundos. Assim que você
abre o app, encontra uma mensagem sobre a chamada perdida.

### Chamadas em grupo

Você também pode fazer chamadas em grupo, com várias pessoas participando ao
mesmo tempo. A chamada é organizada por uma árvore de retransmissão
inteligente, de modo que nem todo participante precisa estar diretamente
conectado a todos os outros. Todas as conversas são criptografadas do início
ao fim.

Cada membro do grupo pode iniciar uma chamada em grupo. Dois participantes
que não são contatos um do outro nunca veem o endereço de internet do outro:
o som e a imagem deles passam por um participante que é contato de ambos.
Se não existe tal participante, os dois não ficam conectados, e o bloco diz
"Nenhum contato em comum na chamada". Se uma retransmissão está
sobrecarregada, o som permanece, e o vídeo cai para esse par.

### Criptografia em chamadas

Todas as chamadas são criptografadas com chaves de uso único, que existem
apenas durante a conversa. Após desligar, essas chaves são apagadas
imediatamente. Ninguém pode descriptografar uma conversa passada depois.

Sendo honesto: chamadas rodam, sempre que possível, diretamente entre os
aparelhos, pois até um pequeno atraso atrapalha a fala. Ao contrário das
mensagens, seu provedor de internet pode, por isso, ver em uma chamada com
qual endereço de internet você está conectado. O que vocês dizem, ele não vê.

Em uma chamada, seu contato também vê o seu endereço de internet. Se você
não quer isso com um contato, desligue no menu dele "Permitir chamadas"
(padrão: ligado). Se você desligar mais tarde, continua conhecido para ele
um endereço que ele já tenha visto.

---

## 8. Calendário

O Cleona contém um calendário integrado, que funciona criptografado e de forma
completamente descentralizada -- sem serviço de nuvem.

### Visões

O calendário oferece cinco visões: dia, semana, mês, ano e uma visão de
tarefas. Alterne entre elas pelas abas na parte superior da tela do
calendário.

### Criar compromissos

Toque em um horário ou use o botão de adicionar para criar um novo
compromisso. Você pode inserir título, data, hora, local e notas. Os
compromissos são armazenados criptografados no seu aparelho.

### Compromissos recorrentes

Os compromissos podem se repetir diariamente, semanalmente, mensalmente ou
anualmente. Você pode ajustar o padrão (por exemplo, toda segunda terça, no
primeiro dia do mês) e definir uma data final ou um número de repetições.

### Convidar contatos

Ao criar ou editar um compromisso, você pode convidar seus contatos do
Cleona. Eles recebem um convite de calendário criptografado e podem responder
com confirmação, recusa ou talvez. Alterações no compromisso são enviadas
automaticamente a todos os convidados.

### Indicação de livre/ocupado

Você pode compartilhar sua disponibilidade com contatos, sem revelar os
detalhes do compromisso. Há três níveis de privacidade: detalhes completos,
apenas blocos de tempo, ou oculto. Você pode definir um padrão e substituí-lo
por contato.

### Lembretes

Os compromissos podem ter lembretes que disparam uma notificação do sistema
antes do início do compromisso. Você pode silenciar lembretes se necessário.

### Sincronização externa de calendário

O Cleona pode sincronizar com serviços de calendário externos:

- **CalDAV** -- Conecte-se a qualquer servidor compatível com CalDAV
  (Nextcloud, Radicale etc.).
- **Google Agenda** -- Sincronização pela Google Calendar API com
  autenticação OAuth2 segura.
- **Servidor CalDAV local** -- O Cleona pode iniciar um servidor CalDAV local
  no seu aparelho, de modo que apps de calendário de desktop (Thunderbird,
  Outlook, Apple Calendar, Evolution) possam sincronizar com seu calendário
  do Cleona.
- **Calendário do sistema Android** -- Compromissos do Cleona podem ser
  transferidos para o app de calendário integrado do seu aparelho Android.
- **Arquivos ICS** -- Importe e exporte compromissos no formato iCalendar
  padrão.

### Exportação em PDF

Você pode imprimir ou exportar qualquer visão do calendário (dia, semana, mês,
ano) como documento PDF.

---

## 9. Enquetes

Você pode criar enquetes em qualquer chat ou grupo, para reunir opiniões ou
planejar datas.

### Tipos de enquete

O Cleona suporta cinco tipos de enquetes:

- **Escolha única** -- Participantes escolhem uma opção.
- **Escolha múltipla** -- Participantes podem escolher várias opções.
- **Enquete de datas** -- Encontre uma data que sirva para todos. Cada
  participante marca datas como disponível, talvez, ou não disponível.
- **Escala** -- Avalie algo em uma escala numérica (por exemplo, 1 a 5).
- **Texto livre** -- Participantes escrevem sua própria resposta.

### Criar enquete

Abra um chat e toque no ícone de enquete (ou use o menu de anexos). Escolha o
tipo de enquete, formule sua pergunta e as opções, e envie a enquete. Ela
aparece como mensagem no chat.

### Votar

Toque em uma enquete para dar seu voto. Você pode alterar ou retirar seu voto
a qualquer momento.

### Votação anônima

As enquetes podem ser configuradas para votação anônima. Quando ativada, os
votos são criptograficamente anônimos -- ninguém, nem mesmo o criador da
enquete, pode ver quem votou no quê. A contagem de votos permanece visível.

### Enquete de datas para o calendário

Quando uma enquete de datas é concluída, a data vencedora pode ser convertida
com um toque diretamente em um compromisso do calendário.

---
## 10. Múltiplas identidades

### Por que múltiplas identidades?

Imagine que você queira separar sua vida profissional da sua vida privada --
semelhante a ter dois números de telefone diferentes, mas sem um segundo
celular. No Cleona você pode usar várias identidades em um aparelho. Cada
identidade tem um nome próprio, uma foto de perfil própria, contatos próprios
e conversas próprias.

### Criar nova identidade

1. Na barra superior, você vê sua identidade atual como uma aba.
2. Toque no sinal de mais (+) à direita das suas abas de identidade.
3. Digite um nome para a nova identidade.
4. Pronto -- a nova identidade fica ativa imediatamente.

### Alternar entre identidades

Basta tocar na aba de identidade na barra superior. A alternância é
imediata -- sem tempo de espera, sem recarregar.

### Todas rodam ao mesmo tempo

Um ponto importante: todas as suas identidades estão ativas ao mesmo tempo.
Mesmo quando você está sendo exibido como "Profissional", sua identidade
"Privada" continua recebendo mensagens. Você não perde nada, não importa qual
identidade esteja selecionada no momento.

### Página de detalhes da identidade

Quando você toca na aba da sua identidade ativa no momento, abre-se a página
de detalhes. Aqui você pode:

- Exibir seu QR-Code para contatos.
- Alterar ou remover sua foto de perfil.
- Adicionar uma descrição de perfil.
- Alterar seu nome de exibição.
- Escolher um design (skin) para esta identidade.
- Excluir a identidade, caso não precise mais dela.

### Excluir identidade

Quando você exclui uma identidade, seus contatos são notificados. A
identidade e todos os dados associados são removidos do seu aparelho. Esse
processo é irreversível.

---

## 11. Vários aparelhos

### Uma identidade, um aparelho -- por enquanto

Uma identidade roda hoje em um aparelho. Um segundo aparelho para a mesma
identidade virá numa versão posterior; nas configurações, em "Dispositivos" ->
"Gerenciar dispositivos", "Emparelhar outro aparelho" aparece, por isso,
ainda como "Ainda não disponível".

Quando isso chegar, vale o seguinte: todos os aparelhos têm os mesmos
direitos, não há aparelho principal. Você configura um novo aparelho com as
suas 24 palavras, e um dos seus aparelhos até então aprova. No máximo
5 aparelhos.

Se você digitar hoje as suas 24 palavras em um aparelho novo, você se muda: a
identidade é restaurada no aparelho novo, e o seu aparelho anterior a remove
de si depois (veja o capítulo 12).

Em vários aparelhos, você pode usar hoje identidades diferentes
(capítulo 10).

### Rotacionar chaves da identidade

Se você suspeita que alguém teve acesso às suas chaves, pode gerar novas
chaves em "Gerenciar dispositivos" -> "Rotacionar chaves". Seus contatos são
notificados, seus convites abertos são revogados. Importante: depois disso,
as 24 palavras sozinhas reconstituem apenas as chaves antigas. Crie, por
isso, logo em seguida um novo pacote de recuperação; restaurar você só
consegue, então, junto com esse pacote.

---

## 12. Recuperação

### Usar a frase-semente

Se você perde seu aparelho ou configura um novo:

1. Instale o Cleona no aparelho novo.
2. Escolha, no início, "Restaurar".
3. Digite suas 24 palavras.
4. O Cleona recria delas todas as suas identidades -- com as mesmas chaves de
   antes. Para seus contatos, você é a mesma pessoa.

### O que volta -- e o que não volta

Sua identidade está nas 24 palavras, seus contatos e seu histórico não. De
volta vem o seu acesso à rede pelo **pacote de recuperação**: seu aparelho
deixa um pequeno pacote criptografado na rede. Apenas suas 24 palavras
conseguem encontrá-lo e abri-lo. Nele consta o que seu aparelho novo precisa
para alcançar seus contatos novamente, e o que, enquanto isso, ficou
guardado para você na rede. Para isso, nenhum contato precisa estar online.

O histórico de chat anterior não é trazido de volta por uma restauração.

O pacote de recuperação vive 7 dias e é renovado pelo seu aparelho enquanto
ele roda; nas configurações você vê até quando ele vale. Se por mais de
7 dias nenhum dos seus aparelhos rodou, ele está vencido. As 24 palavras
restauram sua identidade mesmo assim, mas seus contatos você precisa
convidar de novo; o que, enquanto isso, ficou guardado para você na rede,
está perdido.

### Restaurar significa mudar de aparelho

Se o seu aparelho anterior descobrir mais tarde que a identidade foi
restaurada em outro lugar, ele a remove de si -- junto com o histórico dela.
Por isso: quem tem as suas 24 palavras pode, dessa forma, pegar a sua
identidade do seu aparelho. Até todos os contatos estarem de volta, o app o
lembra; com "Concluir e renovar as chaves" você encerra a restauração você
mesmo.

### O que ninguém consegue restaurar

Isso é importante, e por isso o dizemos claramente:

- **Ninguém além de você pode restaurar sua identidade.** Nem o
  desenvolvedor, nem um suporte, e também não seus contatos -- não importa
  quantos sejam. Não existe uma chave-mestra nem uma parte da sua chave que
  estivesse depositada junto de outros.
- **Se você perdeu as 24 palavras e não tem mais aparelho, sua identidade
  está perdida.** Resta apenas criar uma nova e convidar seus contatos de
  novo.

A melhor proteção: anote as 24 palavras em papel e guarde-as em segurança.

---
## 13. Configurações

As configurações você acessa pelo ícone de engrenagem no canto superior
direito.

### Notificações e toques

- Escolha entre seis toques diferentes para chamadas recebidas.
- Defina um som de mensagem.
- Em aparelhos Android, você pode adicionalmente ativar ou desativar a
  vibração.
- **"Silenciar tudo"** deixa, neste aparelho, nenhuma mensagem mais tocar,
  vibrar ou se anunciar -- para todas as identidades. Chamadas continuam
  tocando.
- **"Horas de silêncio"** você define por identidade com De/Até. Nesse
  período, nenhuma mensagem dessa identidade toca, vibra nem se anuncia; as
  mensagens chegam mesmo assim.
- **"Notificações sem conteúdo"** (padrão: desligado) mostra apenas que uma
  mensagem, um convite ou um lembrete chegou -- sem remetente, nome e texto.
  Chamadas continuam mostrando o nome.
- O que chega de uma vez após a inicialização, o Cleona anuncia numa
  notificação coletiva ("5 novas mensagens em 2 conversas"); tudo o que vem
  depois, individualmente. Um toque numa notificação de mensagem abre a
  conversa, também em outra identidade.

### Designs (skins)

O Cleona oferece dez designs diferentes: Teal, Ocean, Sunset, Forest,
Amethyst, Fire, Storm, Slate, Gold e Contrast. O design Contrast atende ao
nível mais alto de acessibilidade (WCAG AAA) e é particularmente legível
com visão reduzida.

Cada identidade pode ter seu próprio design. Você altera o design na página
de detalhes da identidade (toque na aba de identidade ativa).

Adicionalmente, você pode, nas configurações em "Aparência", alternar entre
tema claro, escuro e o tema do sistema.

### Alterar idioma

O Cleona está disponível em 34 idiomas, incluindo idiomas com escrita da
direita para a esquerda (por exemplo, árabe, hebraico). Altere o idioma nas
configurações em "Idioma".

### Arquivamento de mídia

Se você tem em casa um armazenamento de rede (NAS) ou uma pasta compartilhada,
o Cleona pode mover suas mídias automaticamente para lá. São suportados SMB,
SFTP, FTPS e WebDAV.

O armazenamento em níveis funciona assim:
- Os primeiros 30 dias: tudo permanece no seu aparelho.
- Após 30 dias: uma imagem de pré-visualização permanece no aparelho, o
  original é arquivado.
- Após 90 dias: apenas uma pequena imagem de pré-visualização permanece no
  aparelho.
- Após um ano: apenas um marcador permanece, o original está seguro no
  arquivo.

Você pode tocar a qualquer momento em uma mídia arquivada para trazê-la de
volta -- desde que esteja conectado à sua rede doméstica. Mídias
particularmente importantes podem ser fixadas, para que nunca sejam movidas.

Em "Orçamento de armazenamento", você define quantos MB de mídias permanecem
no aparelho (padrão: 100 MB no celular, 2 GB no computador). Quando enche,
a mídia não fixada mais antiga é arquivada primeiro. Um original só é
excluído quando está seguro no arquivo -- as mensagens de texto permanecem
sempre.

### Transcrição para mensagens de voz

Quando ativado, suas mensagens de voz são convertidas em texto localmente no
seu aparelho (com o modelo de código aberto Whisper). O texto transcrito é
enviado junto com a gravação ao seu interlocutor. A transcrição acontece
completamente no seu aparelho -- nenhum dado vai a serviços externos.

Qual modelo (tiny, base, small) é baixado, você define uma vez por aparelho;
o idioma (automático ou fixo), por identidade.

### Download automático

Você pode definir a partir de que tamanho as mídias devem ser baixadas
automaticamente. Assim você pode, por exemplo, deixar imagens carregarem
automaticamente, mas decidir manualmente sobre vídeos grandes.

### Dispositivos

Em "Dispositivos" -> "Gerenciar dispositivos", você vê este aparelho.
Emparelhar um novo aparelho virá numa versão posterior (capítulo 11).

### Rede

O Cleona não precisa de configurações de rede para funcionar. Há
três interruptores de rede:

- **Liberação de porta no roteador** (padrão: ligado). O Cleona pede ao seu
  próprio roteador que abra uma porta para o Cleona. Se funciona, seu
  aparelho fica melhor alcançável para os outros e ajuda a rede. O Cleona
  fala, nisso, apenas com seu roteador, não com a internet.
- **Registros de endereço públicos** (padrão: ligado). Se seu aparelho ainda
  tem poucos vizinhos, ele procura em um diretório público (Nostr) por outros
  pontos de entrada, e se ele mesmo é bem alcançável, registra-se lá. O
  registro contém um endereço, nenhum nome e nenhum contato. Se você o
  desliga, seu aparelho encontra vizinhos apenas por convites, pela rede
  local e pelos vizinhos que já conhece.
- **Menos pacotes de cobertura na rede Wi-Fi** (padrão: desligado). Na rede
  Wi-Fi ou no cabo, você pode desligar os pacotes de cobertura vazios. Mas
  então volta a ser visível, ali, quando você escreve. No celular não há
  esse interruptor -- lá o Cleona envia, de qualquer forma, apenas um pacote
  de cobertura por minuto.

O tráfego de cobertura como um todo não pode ser desligado. Isso é
intencional: só se ele sempre roda, a atividade do seu aparelho não diz nada
sobre se você está escrevendo no momento.

Acima dos três interruptores está o **"Modo de poupança de dados"**: no
celular, o Cleona o sugere, mas nunca o ativa sozinho. Ele economiza dados,
mas em contrapartida o seu aparelho fica mais fácil de reconhecer de fora.

Abaixo, você configura o **"Cache para multimédia de outras pessoas"**: o
seu aparelho guarda por até 7 dias partes criptografadas de mídias de outras
pessoas, para que elas alcancem seus destinatários (padrão: 100 MB no
celular, 1 GB no computador). Um tamanho menor libera o espaço
imediatamente -- as partes mais antigas primeiro.

---

## 14. Segurança

### O que significa criptografia pós-quântica?

A criptografia atual baseia-se em problemas matemáticos que são extremamente
difíceis de resolver para computadores normais. Computadores quânticos
poderão resolver alguns desses problemas rapidamente no futuro. A
criptografia pós-quântica usa procedimentos adicionais que resistem mesmo a
computadores quânticos.

O Cleona combina ambas as abordagens: criptografia clássica pela
confiabilidade e procedimentos pós-quânticos pela segurança futura. Assim
você está protegido contra ameaças atuais e futuras ao mesmo tempo.

Para cada mensagem individual é gerada uma chave própria. Mesmo se um
atacante quebrasse a chave de uma mensagem, ele não poderia ler nenhuma outra
mensagem com isso.

### Por que sem servidor é mais seguro

Em mensageiros convencionais, suas mensagens passam pelos servidores do
provedor. Mesmo que estejam criptografadas lá: o provedor tem acesso a
metadados (quem se comunica quando com quem, com que frequência, de onde) e
precisa, em certas circunstâncias, entregá-los por ordem judicial.

No Cleona não há esse ponto central. Não há lugar onde todos os metadados
convergem, nem diretório no qual se possa consultar quem você é ou quem você
conhece.

### Quem vê que você está escrevendo com alguém?

A criptografia protege **o que** você escreve. Igualmente importante é que
nenhum observador isolado fique sabendo **com quem** e **quando** você
escreve. Para isso o Cleona cuida assim:

- **Na internet nunca diretamente.** Se seu aparelho enviasse uma mensagem
  direto ao endereço de internet do seu interlocutor, seu provedor poderia
  ver com quem você escreve. Por isso uma mensagem na internet passa sempre
  pelos seus vizinhos fixos: o seu e o do seu interlocutor.
- **Vizinhos em quem você confia.** Seus vizinhos fixos são, sempre que
  possível, aparelhos dos seus próprios contatos -- até três que estejam
  alcançáveis de fora no momento. Se um cai, outro contato assume. Um
  contato não se compra com servidores; um nó qualquer na rede sim. Se você
  ainda não tem nenhum contato alcançável, o Cleona pega outro vizinho. Seu
  convite nunca nomeia nenhum dos seus contatos, para que ninguém, por meio
  dele, fique sabendo o endereço de um amigo.
- **Códigos em vez de nomes.** Os vizinhos não veem nomes nem
  identificadores, mas apenas um código. Ele vale exatamente para vocês dois,
  em uma direção, por um dia -- no dia seguinte é outro. Seu vizinho sabe de
  onde o pacote vem, mas não para onde ele vai no final. O vizinho do seu
  interlocutor sabe para onde ele vai, mas não de onde veio. No caso normal,
  ninguém no caminho vê ambas as pontas.
- **O tráfego de cobertura.** Seu aparelho envia continuamente, em
  intervalos irregulares, pacotes de cobertura aos seus vizinhos. Eles têm o
  mesmo tamanho que pacotes reais, passam pela mesma porta e, de fora, não
  podem ser distinguidos deles. Se um humano está escrevendo no momento ou o
  aparelho apenas está ligado não é perceptível. Suas mensagens nunca
  esperam pelo tráfego de cobertura -- elas partem imediatamente, ele apenas
  roda em paralelo.

**O que o tráfego de cobertura custa:** Na rede Wi-Fi cerca de 13 MB por dia.
No celular, o Cleona envia apenas um pacote de cobertura por minuto, o que dá
aproximadamente 1,7 MB por dia. O motivo da redução no celular não é o
volume de dados, mas a bateria: cada pacote acorda o modem de rádio.

**O que o Cleona não pode ocultar** -- falando honestamente:

- Nenhum **único** observador vê quem escreve com quem -- nem seu provedor
  nem os nós no caminho. Quem, porém, monitora **ambas as pontas ao mesmo
  tempo**, por exemplo um Estado que observa sua conexão e a do seu
  interlocutor, ou prende ambos os vizinhos, consegue, ao longo do tempo,
  associar: pacote sai em você, logo em seguida pacote entra no seu
  interlocutor. Repetido com frequência suficiente, isso resulta em uma
  conexão.
- O tráfego de cobertura dificulta essa associação, mas não a impede. Ele
  oculta mensagens individuais, não o volume: quem envia muito aumenta o
  tráfego total do seu aparelho.
- Um contato que é seu vizinho fixo fica sabendo **quando** e **quanto** você
  envia e recebe -- não com quem e não o quê. Se a ameaça vem do seu próprio
  círculo, você pode excluir cada contato disso (veja o capítulo 3, "Nunca
  usar como vizinho fixo").
- Se dois novos usuários têm apenas o mesmo único vizinho, a mensagem deles
  passa por exatamente esse nó, e ele vê ambas as pontas. Assim que um dos
  dois tem outros vizinhos, isso acaba.
- Seu convite contém seus endereços de internet. Quem tem a linha de texto
  vê onde você está online -- dê-a apenas a pessoas em quem você confia.
- Um vizinho que repassa vê que dois códigos trocam pacotes -- não quem está
  por trás, e não o que está dentro.
- Um sinal de uma chamada em andamento pode, quando o primeiro vizinho não
  responde no momento, passar por um nó que vê ambas as pontas; ele fica
  sabendo que vocês telefonam juntos.
- Um arquivo grande ao qual você deu aprovação é visto pelo computador que o
  repassa ou o guarda, em ambas as pontas (veja o capítulo 4).
- Em chamadas, a proteção contra o provedor não se aplica, e seu contato vê
  o seu endereço de internet (veja o capítulo 7).

### O que acontece quando seu interlocutor está offline?

1. O Cleona inicia todos os caminhos adequados ao mesmo tempo: na mesma rede
   Wi-Fi direto, na internet por dois vizinhos -- e adicionalmente a caixa
   de correio.
2. Para a caixa de correio, o Cleona deixa a mensagem criptografada com três
   vizinhos. Assim que dois confirmam o recebimento, ela vale como
   depositada.
3. O Cleona escolhe para isso preferencialmente vizinhos onde seu
   interlocutor também procura -- primeiro o vizinho que o convite dele
   nomeia.
4. A mensagem espera ali por até 7 dias. Quando seu interlocutor volta, ele
   a recolhe e confirma o recebimento. Só então você vê dois vistos.

A caixa de correio só pode ser esvaziada pelo seu interlocutor: recolher e
excluir só funciona com uma chave que só ele possui, e a exclusão só ocorre
depois que ele confirma o recebimento. Os vizinhos veem apenas pacotes
criptografados sob um valor que muda todos os dias.

### Desconhecidos não passam

De alguém que não é seu contato nem membro de um grupo em comum, o Cleona
aceita exatamente duas coisas: a
pergunta pelas suas chaves públicas, enquanto um dos seus convites está
aberto, e um pedido de contato. O pedido precisa trazer um convite válido
seu, e o remetente precisa ter resolvido antes uma tarefa computacional.
Tudo o mais -- mensagens, chamadas, arquivos -- é descartado antes que chegue
ao app. Quem só tem o seu cartão de visitas impresso, portanto, não pode
simplesmente lhe telefonar. Um membro de um grupo em comum alcança você
apenas nesse grupo -- com mensagens de grupo e chamadas de grupo, nunca
individualmente.

### Anticensura

O Cleona é construído de modo que é difícil bloqueá-lo:

- **Sem servidor, sem endereço fixo.** No app não consta nenhum endereço que
  se pudesse bloquear, e a rede não depende de nenhum nó isolado.
- **Sem porta fixa.** Cada aparelho escolhe uma porta aleatória no primeiro
  início. Não há número de porta conhecido pelo qual se pudesse reconhecer
  tráfego do Cleona.
- **Como dados aleatórios.** O estabelecimento de conexão entre dois
  aparelhos é codificado de modo a não ser distinguível de dados aleatórios.
- **Muitas entradas.** Cada convite, cada vizinho e cada aparelho na mesma
  rede Wi-Fi é um possível caminho de volta à rede.

### Armazenamento seguro de chaves

Em plataformas suportadas, o Cleona armazena suas chaves de criptografia no
keyring seguro do sistema operacional (Android Keystore, iOS Keychain,
macOS Keychain). Onde disponível, isso oferece proteção por hardware para
suas chaves.

### Criptografia do banco de dados

Suas mensagens e conversas estão em um banco de dados criptografado -- um
próprio para cada identidade, cada um com sua própria chave. Criptografado
não é apenas o banco de dados em si, mas também seus arquivos temporários;
nada é escrito sem criptografia no disco, nem mesmo por pouco tempo.
Configurações, contatos e mídias também estão armazenados criptografados.

As chaves são derivadas das suas 24 palavras e existem apenas no seu
aparelho. Mesmo quem pega seu aparelho nas mãos e lê os dados encontra, sem
essas chaves, apenas dados ilegíveis.

Só fica sem criptografia o que você mesmo tira para fora de Cleona:
- quando você salva um arquivo de um chat no seu aparelho,
- quando você coloca uma imagem nas suas imagens com o botão de captura de
  tela,
- quando você compartilha algo com outro app,
- quando você configura o arquivamento de mídia (capítulo 13): os originais
  arquivados ficam sem criptografia no seu armazenamento de rede em casa,
  para que você possa abri-los lá também sem o Cleona,
- quando você espelha compromissos no calendário do sistema Android: ali,
  outros apps com acesso ao calendário podem lê-los.

O que saiu dessa forma não é excluído junto com a mensagem e não expira
junto com ela.

### Proteção na tela

No Android, no Windows e no macOS, o Cleona não permite a gravação de tela
por outros apps. Se você precisa de uma imagem, use o botão de captura de
tela na barra superior: ele coloca a imagem nas suas imagens -- sem
criptografia. Numa conversa em que encaminhar não é permitido, não há
captura de tela.

---

## 15. Atualizações de software

### Como obtenho atualizações?

O Cleona pode ser atualizado por diversos caminhos. O objetivo é que você
possa receber atualizações mesmo quando canais de distribuição individuais
falham ou são bloqueados:

1. **App Store / Play Store:** Assim que o Cleona aparecer lá e você o
   tiver instalado por uma loja, você recebe as atualizações como de costume
   pela loja. No iPhone, as atualizações chegam pelo TestFlight.
2. **GitHub Releases:** Na página do GitHub do projeto, você encontra pacotes
   de instalação assinados para todas as plataformas.
3. **Atualizações pela rede:** O Cleona pode obter uma atualização direto
   pela rede -- sem servidor de download. A nova versão é dividida em pedaços
   com correção de erros, que se distribuem pela rede; uma parte deles até
   viaja no tráfego de cobertura. Seu aparelho reúne pedaços suficientes e
   monta a atualização. Geralmente é transferida apenas a mudança -- poucos
   MB em vez do app inteiro. Isso vale para Linux, Windows e Android; no
   macOS, você baixa novas versões do site ou do GitHub.
4. **Links de convite:** Você pode criar links de convite que contêm tudo o
   que um novo usuário precisa para instalar o Cleona e se conectar à rede.
5. **Transferência física:** Em ambientes sem internet, você pode repassar o
   Cleona por pen drive USB ou na rede local a outros.

### Como decorre uma atualização

1. O Cleona reúne os pedaços de uma nova atualização automaticamente em
   segundo plano e os monta.
2. Só quando a atualização está **completa** e sua **assinatura foi
   verificada**, o Cleona a oferece a você. Você nunca recebe, portanto, uma
   atualização pela metade ou não verificada.
3. Se você toca em "Instalar", a instalação começa sem nova pergunta. No
   Android, adicionalmente, o sistema mostra seu diálogo de instalação.

Versões mais antigas não são oferecidas -- uma atualização só vai para a
frente. Se uma versão é tão antiga que não consegue mais trabalhar com a
rede, o Cleona indica isso claramente e pede que você atualize.

### Verificação de assinatura

Cada atualização é duplamente assinada: com um procedimento clássico e um
pós-quântico. O Cleona verifica ambas as assinaturas automaticamente. Assim
fica garantido que apenas atualizações do desenvolvedor oficial são aceitas
-- mesmo que a atualização tenha vindo pela rede de aparelhos de terceiros.
Uma atualização nunca surge automaticamente a partir do desenvolvimento, mas
apenas quando o desenvolvedor a assina manualmente.

---
## 16. Perguntas frequentes

### "Posso usar o Cleona sem internet?"

O Cleona precisa de uma conexão de rede, mas não necessariamente de internet:
na mesma rede Wi-Fi, aparelhos com Cleona se encontram sozinhos e podem
escrever entre si totalmente sem acesso à internet. Vocês não precisam
estar online ao mesmo tempo, você e seu interlocutor: se ele está offline, a
mensagem espera por até 7 dias na caixa de correio com três vizinhos, até
que ele a recolha.

### "E se eu perder minha frase-semente?"

Enquanto ainda houver um aparelho rodando com sua identidade, nada está
perdido -- ali você simplesmente continua escrevendo. No aparelho em que você
criou a identidade, você pode, na maioria das vezes, consultar novamente as
24 palavras (veja o capítulo 2). Não confie nisso: uma reinstalação remove
essa cópia, e, no Android, remover ou alterar o bloqueio de tela também a
destrói. Se você não tem nem as palavras nem
um aparelho, não há como voltar -- nem por seus contatos, pelo
desenvolvedor ou qualquer outra pessoa. Por isso é tão importante guardar as
24 palavras em segurança.

### "Alguém pode ler minhas mensagens?"

Não. Cada mensagem é criptografada com uma chave de uso único, que vale
apenas para essa única mensagem. Apenas você e seu interlocutor podem
descriptografar a mensagem. Não há servidor central, nem chave-mestra
e nem acesso para o desenvolvedor. Mesmo se um aparelho no caminho de
transporte retransmitir a mensagem, ele vê apenas uma massa de dados
criptografada e um código. Seu vizinho sabe que o pacote vem de você, mas
não para quem vai; o vizinho do seu interlocutor sabe para quem vai, mas
não de quem.

### "Por que não preciso de número de telefone?"

Porque sua identidade é puramente criptográfica. Em vez de um número de
telefone ou endereço de e-mail vinculado ao seu nome real, um par de chaves
gerado no seu aparelho o identifica. Você adiciona contatos por QR-Code, NFC
ou pela linha de texto do seu convite -- não por uma agenda telefônica. Isso
significa
mais privacidade, porque sua conta de mensageiro não está ligada à sua
identidade real.

### "Como encontro pessoas no Cleona?"

O Cleona propositalmente não tem busca de contatos por número de telefone ou
nome -- isso seria um problema de privacidade. Em vez disso, você troca
convites diretamente: por QR-Code, NFC ou como linha de texto por outro
caminho. É como trocar cartões de visita em vez de consultar a agenda
telefônica.

### "O Cleona funciona também no exterior?"

Sim. Desde que você tenha uma conexão de internet, o Cleona funciona em todo
o mundo. Como não há servidor central nem endereço fixo, o serviço não pode
ser simplesmente desligado para determinados países. Como o Cleona dificulta
bloqueios, leia no capítulo "Segurança", em "Anticensura". Um país,
porém, que bloqueie todo tráfego desconhecido na fronteira, também consegue
 deter o Cleona.

### "O Cleona é gratuito?"

Sim. O Cleona é utilizável gratuitamente e sem anúncios. Como não há
servidor central, também não há custos de servidor para a operação. Nas
configurações, em "Apoie Cleona" -> "Doar", você pode apoiar voluntariamente
o desenvolvimento.

### "Minha mensagem tem só um visto -- o que significa?"

A mensagem está a caminho, mas seu interlocutor ainda não confirmou o
recebimento -- na maioria das vezes, porque ele está offline no momento. Isso
não é erro: a mensagem espera por até 7 dias na caixa de correio. Assim que
ele a recolhe, você vê dois vistos. Um relógio significa que ainda nenhum
caminho levou a mensagem -- ela parte sozinha assim que houver um; um sinal
de aviso, que ela ficou 14 dias sem encontrar nenhum caminho e você pode
reenviá-la.

### "Por que as mensagens chegam atrasadas no meu iPhone?"

O iOS não deixa apps rodarem permanentemente em segundo plano. Só de vez em
quando o iOS acorda Cleona por um breve momento; quando isso acontece, ele
decide. Cleona recolhe então tudo. Assim que você abre o app, Cleona recolhe o
que foi guardado para você.

### "Posso mudar do WhatsApp para o Cleona?"

Sim, mas você não pode transferir seus chats do WhatsApp. O Cleona e o
WhatsApp são sistemas fundamentalmente diferentes. Você precisa adicionar
seus contatos individualmente no Cleona. O mais simples é enviar a linha de
texto do seu convite aos seus contatos. Cada pedido que chega assim você
confirma, em "Pedidos".

### "Posso usar o Cleona em vários aparelhos ao mesmo tempo?"

Ainda não. Um segundo aparelho para a mesma identidade virá numa versão
posterior (capítulo 11). Em vários aparelhos, você pode usar hoje
identidades diferentes.

### "Como obtenho atualizações se a App Store estiver bloqueada?"

O Cleona pode obter atualizações direto pela rede, sem depender de uma
App Store, de um site ou de um servidor de download. Se outro aparelho na
rede tem a versão mais recente, seu aparelho pode baixar a atualização de lá.
A autenticidade é verificada por uma assinatura digital do desenvolvedor.
Como alternativa, um contato pode repassar o app a você por link de convite ou
pen drive USB. Mais sobre isso no capítulo
"Atualizações de software".

---

## Ajuda e contato

Se você tem perguntas ou se depara com um problema, encontra informações
atuais no site do Cleona e no GitHub. Como o Cleona é um projeto
descentralizado, não há suporte ao cliente clássico -- mas uma comunidade
ativa que ajuda de bom grado.

---

*Este manual descreve o Cleona Chat versão 4.2. Funções individuais
podem mudar ou ser ampliadas em versões mais recentes.*