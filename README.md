# Deployment of OKD in the Yandex cloud
Полуавтоматическая установка.
<ol>
<li>Склонировать к себе гит репозиторий</li>
<pre><code>git clone https://github.com/aluera/okd-yc.git</code></pre>
<li>Внести свои правки в файл okd_config.py</li>
<li>Выполнить: <pre><code>python initial.py</code></pre></li>
<li>Выполнить: <pre><code>python install_okd.py</code></pre>
<li>
*`В процессе работы скрипта необходимо включит NAT для всей подсети https://cloud.yandex.ru/docs/vpc/operations/enable-nat`*</li>
<li>*`Удалить созданный object storage`*</li>
</li>
</ol>
____
Ручная установка:
<ol>
<li>Склонировать к себе гит репозиторий</li>
<pre><code>git clone https://github.com/aluera/okd-yc.git</code></pre>
<li>Внести свои правки в файл okd_config.py</li>
<li>Выполнить: <pre><code>python initial.py</code></pre></li>
<li>Перейти в папку terraform и выполнить: <pre><code>terrafrom apply -auto-approve</code></pre></li></li>
<li>После развёртывания необходимо добавить ip-адрес балансировщика в /etc/host/ узла, с которого планируете запускать скрипты.<pre><code>xxx.xxx.xxx.xxx api.$cluster_name.$dns_zone.ru</code></pre></li>
<li>Установить master ноду: <pre><code>sh ./scripts/wait-for-bootstrap.sh</code></pre> </li>
<li>В файле terraform.tfvars выставить <pre><code>bootstrap_count = 0</code></pre> сохранить файл и выполнить:
<pre><code>terrafrom apply -auto-approve</code></pre></li>
<li>Подписать все ожидающие сертификаты: <pre><code>sh ./scripts/sign-csr-all.sh</code></pre> </li>
<li>Установить worker ноду: <pre><code>sh ./scripts/wait-for-install.sh</code></pre> </li>
</ol>
