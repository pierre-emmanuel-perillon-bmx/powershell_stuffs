Param(
    [parameter(Mandatory=$false)][ValidateSet('PROD','HPRD','METIER')][String]$environnement='METIER',
    [parameter(Mandatory=$false)][string]$configFile = 'config_LPT.txt',
    [string] $caccia_user = '',
    [switch] $no_password_store = $false,
    [switch] $no_password_ask = $false,
    [switch] $no_open_report = $false,
    [switch] $no_abreviate = $false,
    [switch] $extract_all = $false,
    [switch] $reconciliate = $true,
    [int]    $keep_reports_days = 360,
    [switch] $trim_login = $true,
    [string] $report_tag ='KYSS'
 )

<#
please create outputDirectory  in the filesystem !!!
 #>

Set-strictmode -version Latest
$pwd = [System.IO.Path]::GetDirectoryName($myInvocation.MyCommand.Definition) 

$config = New-Object -TypeName psobject
Add-Member -InputObject $config -MemberType NoteProperty -Name url_PROD           -value 'https://kyss.local/'
Add-Member -InputObject $config -MemberType NoteProperty -Name url_HPRD           -Value 'https://hprod.kyss.local/'
Add-Member -InputObject $config -MemberType NoteProperty -Name url_HPME           -Value 'https://metier.hprod.kyss.local/'
Add-Member -InputObject $config -MemberType NoteProperty -Name site_PROD          -value 'kyss.local'
Add-Member -InputObject $config -MemberType NoteProperty -Name site_HPRD          -Value 'hprod.kyss.local'
Add-Member -InputObject $config -MemberType NoteProperty -Name site_HPME          -Value 'metier.hprod.kyss.local'
Add-Member -InputObject $config -MemberType NoteProperty -Name network_try        -Value 16 
Add-Member -InputObject $config -MemberType NoteProperty -Name project_url        -value "https://.../-/tree/master/PowerKyss"
Add-Member -InputObject $config -MemberType NoteProperty -Name outputReport       -Value "Rapport-[TAG]-[ENVI]-[DATETIME].html"
Add-Member -InputObject $config -MemberType NoteProperty -Name outputDirectory    -Value "Rapports" 
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_uiweb         -value "ui/vault/secrets/secret%2F[NNA]/show/[ENV]/[TEAMTREE]"
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_login         -value "v1/auth/caccia_prod/login/[LOGIN]"
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_kvlist        -value "v1/secret/[NNA]/metadata/[FULLTREE]?list=true"
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_kvget         -value "v1/secret/[NNA]/data/[FULLTREE]"
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_mount         -value 'v1/sys/internal/ui/mounts'
Add-Member -InputObject $config -MemberType NoteProperty -Name kyss_tree          -value "secret/[NNA]/[ENV]/[TEAMTREE]"
Add-Member -InputObject $config -MemberType NoteProperty -Name nosubtree          -value "*****"
Add-Member -InputObject $config -MemberType NoteProperty -Name cachePurgeDays     -Value 60
Add-Member -InputObject $config -MemberType NoteProperty -Name passwordStoreExt   -value ".caccia.secret"
Add-Member -InputObject $config -MemberType NoteProperty -Name reconciliationFile -value "reconciliation-[NNA].csv"
Add-Member -InputObject $config -MemberType NoteProperty -Name reconciliationSepa -value ";"
Add-Member -InputObject $config -MemberType NoteProperty -Name defaultlogin       -value "generic" 
Add-Member -InputObject $config -MemberType NoteProperty -Name prop_user          -value "(username)|(login)|(role_id)" 
Add-Member -InputObject $config -MemberType NoteProperty -Name prop_pass          -value "(password)|(key)|(tocken)|(secret)" 

Add-Member -InputObject $config -MemberType NoteProperty -Name bypassedSecret     -value ('cubbyhole/','identity/','sys/')
Add-Member -InputObject $config -MemberType NoteProperty -Name dateFormat         -value 'ddd yyyy-MM-dd HH:mm:ss' 

Add-Member -InputObject $config -MemberType NoteProperty -Name exitCode -Value @{
'SUCCESS' = 0
'GENERIC_ERROR' = 1
'NO_PASSWORD' = 2
'FAILED_AUTHENTICATION' =3
'NO_CONFIG'= 4
'NETWORK_FAILURE' = 5
'WRITE_ERROR' =6 
}

$runtime = New-Object -TypeName psobject
Add-Member -InputObject $runtime -MemberType NoteProperty -Name cwd               -Value $pwd
Add-Member -InputObject $runtime -MemberType NoteProperty -Name param_address     -value ''
Add-Member -InputObject $runtime -MemberType NoteProperty -Name param_format      -value 'json' 
Add-Member -InputObject $runtime -MemberType NoteProperty -Name roots             -value @()  
Add-Member -InputObject $runtime -MemberType NoteProperty -Name date              -value (get-date)
Add-Member -InputObject $runtime -MemberType NoteProperty -Name env               -value ''
Add-Member -InputObject $runtime -MemberType NoteProperty -Name site              -value ''
Add-Member -InputObject $runtime -MemberType NoteProperty -Name hashprovider      -Value (New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider)
Add-Member -InputObject $runtime -MemberType NoteProperty -Name contentutf8       -Value (New-Object -TypeName System.Text.UTF8Encoding)
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_pass_store     -Value (-not($no_password_store))
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_pass_ask       -Value (-not($no_password_ask))
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_open_report    -Value (-not($no_open_report))
# Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_abreviate      -Value (-not($no_abreviate))
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_abreviate      -Value $false 
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_extract_all    -Value $extract_all
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_reconciliation -Value $reconciliate 

$report_tag=$report_tag -replace '[^\w _]+','';
Add-Member -InputObject $runtime -MemberType NoteProperty -Name reportTag          -Value $report_tag.Substring(0,[Math]::min(48,$report_tag.Length))
Add-Member -InputObject $runtime -MemberType NoteProperty -Name credentialValid    -Value $false 
Add-Member -InputObject $runtime -MemberType NoteProperty -Name purgeReports       -Value $keep_reports_days 
Add-Member -InputObject $runtime -MemberType NoteProperty -Name username           -Value $caccia_user
Add-Member -InputObject $runtime -MemberType NoteProperty -Name passwordAsked      -Value $false
Add-Member -InputObject $runtime -MemberType NoteProperty -Name confile            -Value $configFile
Add-Member -InputObject $runtime -MemberType NoteProperty -Name do_trim            -Value $trim_login
Add-Member -InputObject $runtime -MemberType NoteProperty -Name port               -Value 443

function buildReportFileName([string]$passwd,[string]$env,[datetime] $timestamp,[string]$tag){      
    $tmp = [System.IO.Path]::Combine( $passwd ,$config.outputReport.replace('[ENVI]',$env).replace('[DATETIME]', $timestamp.ToString("yyyyMMdd_HHmmss")).replace('[TAG]',$tag))
    return $tmp
}


function buildReportPath(){
    $out = [System.IO.Path]::Combine($runtime.cwd,$config.outputDirectory)
    if ( -not(Test-Path -Path $out -PathType Container) ){
       New-Item -Path $out -ItemType Directory -ErrorAction Stop
    }
    return $out 
}


function buildTeamtree([string]$team,[string]$subt){
    if ($subt -eq $config.nosubtree ){
        return $team 
    }
    else {
        return $team+"/"+$subt
    }
}

function buildKyssPath([string]$nna,[string]$env,[string]$teamtree){
    return "secret/"+$nna+"/"+$env+"/"+$teamtree
}

function buildKyssLink([string]$nna,[string]$env,[string]$teamtree ){
    ##ui/vault/secrets/secret%2Fdi3/show/qual/appli/K2Q/Mandant_000
    $tmp = $config.kyss_uiweb.replace('[NNA]',$nna).replace('[ENV]',$env).replace('[TEAMTREE]',$teamtree)
    return $runtime.param_address+$tmp 

}

function computeReconciliation([string]$nna, [string]$words){
    foreach( $line in $RECONCILIATION[$nna] ){
        if( $words -imatch $line.search ){
            #exit apres le premier match
            $tmp = '{'+$line.replace+'}'
            return $words -ireplace $line.search, $tmp 
        }
    }
   return $words
}

function findLocalFile( $passwd, $providedName ){
    $item = Get-ChildItem -File -LiteralPath $providedName  -ErrorAction Ignore  | Select-Object -First 1 
    
    if ( ($item | Measure-Object).count -gt 0 ){
        return $item.FullName 
    }

    $item = Get-ChildItem -path $passwd -Filter $providedName -File -ErrorAction Ignore  | Select-Object -First 1 
    if ( ($item | Measure-Object).count -gt 0 ){
        return $item.FullName 
    }

    return [System.IO.Path]::Combine( $passwd , $providedName )
}



function getSytemUser(){
    return $env:USERNAME;
}

function hashPassword([string]$nna,[string]$passwd){
    # return [System.BitConverter]::ToString($runtime.hashprovider.ComputeHash($runtime.contentutf8.GetBytes($nna+$passwd))) -replace "-",""
    return ''
}

function hashAbreviate([string]$hash){
    $tmp1= $hash.substring(0,5)
    $tmp2= $hash.Substring( $hash.Length -5,5)
    return $tmp1+".."+$tmp2     
}

function init-result([string] $nna,[string]$tree){
    return  @{'COUNT'=-1;'ANSWER'=$false;'PSSWD'=@{};'PATH'='secret/'+$nna+'/'+$tree;'TS'=$null;'OPT'='' }
}

function loadReconcilationFile([string]$nna){
    $csvfile = [System.IO.Path]::Combine( $runtime.cwd , $config.reconciliationFile.replace('[NNA]',$nna) )
    if ( Test-Path $csvfile ){
       try {
            $csv = Import-Csv $csvfile -Delimiter $config.reconciliationSepa | Where-Object {
               [string]::IsNullOrEmpty($_.search) -eq $false -and [string]::IsNullOrWhiteSpace($_.replace) -eq $false
            }
        }
        catch {
            $myError = $_.Exception.Message
            Write-Host "Anomalie lors de la lecture du fichier de réconciliation "
            Write-Host -NoNewline "Fichier ignoré: " 
            Write-Host -ForegroundColor Yellow $csvfile 
            Write-Host -ForegroundColor Red $myError
            Write-Host " "
            $csv = @()
        }
    }else{
        Write-Host -NoNewline "Fichier de réconciliation non trouvé: "
        Write-Host -ForegroundColor Yellow $csvfile 
        $csv = @()
    }
    $RECONCILIATION.add($nna,$csv)

}


function parse-secret( $data, [datetime] $ts, [string] $nna,[string]$tree ){  
    $res = init-result $nna $tree 
    
    $res['TS'] = $ts

    $props =Get-Member -InputObject $data -MemberType NoteProperty | Select-Object -ExpandProperty Name | Where-Object { $_ -ne $config.defaultlogin } 

    try{

        $match_user = $props -cmatch $config.prop_user
        $match_pass = $props -cmatch $config.prop_pass

        #contournement pour un bug bizarre 
        # parfois -cmatch répond false, parfois vide
        if ( $match_user -eq $false ){
            $count_user = 0
        }
        else{
            $count_user = ($match_user | Measure-Object ).count
        }

        if ( $match_pass -eq $false ){
            $count_pass = 0
        }
        else {
             $count_pass = ($match_pass | Measure-Object ).count
        }

        #en fonction du nombre de user/mdp trouvé
        if ( $count_user -eq 1 ){   
            if ( $count_pass -eq 0 ){
                $non_structure = $true
            } else {
                $non_structure = $false 
                $login = $data."$match_user"
                $data.PSObject.properties.remove($match_user)
                if ( $runtime.do_trim ){
                    $login=$login.trim()
                }
                if ( $count_pass -eq 1 ){
                    $res['ANSWER'] = 'secret structuré'
                    $password=$data."$match_pass"
                    $data.PSObject.properties.remove($match_pass)
                    $rate = ratePassword $password
                    $hash = hashPassword $nna $password
                    if($runtime.do_abreviate ){
                        $hash = hashAbreviate $hash
                    }
                    $res['PSSWD'].add($login,($rate,$hash))
                    $res['COUNT']=1
                } else { # count_pass -gt 1 
                    $res['ANSWER'] = 'secret structuré avec plusieurs mots de passes'
                    foreach ( $prop_password in $match_pass ){
                        $password=$data."$prop_password"
                        $data.PSObject.properties.remove($prop_password)
                        $rate = ratePassword $password
                        $hash = hashPassword $nna $password
                        if($runtime.do_abreviate ){
                            $hash = hashAbreviate $hash
                        }
                        $res['PSSWD'].add($login+" || "+$prop_password,($rate,$hash))

                    }#fin else count_pass -gt1
                } #fin else count_pass
                $res['COUNT']=$res['PSSWD'].Count                
            } #count_pass -ne 0 
        } elseif ( $count_user -gt 1 ) {         
              if ( $count_pass -eq 1 ){
                   $non_structure = $false
                   $res['ANSWER'] = 'secret structuré avec plusieurs utilisateurs'
                   foreach ( $prop_user in $match_user ){
                        $login = $data."$prop_user"
                        if ( $runtime.do_trim ){
                             $login=$login.trim()
                        }
                        $data.PSObject.properties.remove($prop_user)
                        $password=$data."$match_pass"
                        $rate = ratePassword $password
                        $hash = hashPassword $nna $password
                        $res['PSSWD'].add($login,($rate,$hash))
                   }#foreach
                   $data.PSObject.properties.remove($match_pass)
                   $res['COUNT']=$res['PSSWD'].Count
               }else{
                   $non_structure = $true
               }#count_pass -ne 1 
         } else { #else count-user 
                $non_structure = $true
         }
            
        if ( $non_structure ){
            #secret non structurés
            if ( $count_user -gt 0 -or $count_pass -gt 0 ){
                $res['ANSWER'] = 'secret mal structuré'            
            }
            else{
                $res['ANSWER'] = 'secret non structuré'
            }

            $props | ForEach-Object {
                $password=$data."$_"
                if ( $runtime.do_trim ){
                    $login=$_.trim()
                }else{
                    $login=$_ 
                }

                $rate = ratePassword $password
                $hash = hashPassword $nna $password
                if($runtime.do_abreviate ){
                    $hash = hashAbreviate $hash
                }
                $res['PSSWD'].add($login,($rate,$hash) )
            }
            $res['COUNT']=$res['PSSWD'].Count
        }
        else {
             $res['OPT'] = $data | convertto-json
        }
    }catch {
        $myError = $_.Exception.Message 
        $res['ANSWER'] = $myError 
    }

    return $res 
}




function printHtmlReport([string] $user){
    Write-Output  @"
<!DOCTYPE html>
<html lang="fr">
<head>
"@
    $html='<title>{0} - Extraction {1}</title>' -f $runtime.env,$runtime.date.toString('dddd dd-MM-yyyy HH:mm')
    Write-Output $html 
    Write-Output '<!-- config utilisée '
    $config
    Write-Output '--><!-- options d''execution '
    $runtime
    Write-Output '-->'
    $color_a1 ='whitesmoke'
    $color_a2 ='245,245,245'    
    $color_b1 ='#f5f5ff'
    $color_b2 ='245,245,255' 
    Write-output @"
<style>
html {font-size:0.9rem;}
table {border-collapse:collapse;}
td,th {border:none}
td.errorResult,td.emptyResult {font-style: italic}
tr.errorResult { color:red}
tr.emptyResult { color:Sienna}
tbody tr:nth-child(4n) {background-color:rgba(240, 240, 230, 0.75)}
table.main>thead>tr>th,table.aux th {background-color:lavender;border: 1px solid #AAAAAA;}
table.main>tbody>tr>td,table.aux td {border: 1px solid #AAAAAA;}
table a {text-decoration:none;}
table a:hover {text-decoration:underline}
h1,h2 {color:black;text-shadow: 2px 5px 3px gray;text-align:center}
caption {font-style:italic;}
table.preprod>tbody:nth-child(odd)  { /* https://leaverou.github.io/css3patterns/#seigaiha */
 background-image:
 radial-gradient(circle at 100% 150%, $color_a1 24%, white 24%, white 28%, $color_a1 28%, $color_a1 36%, white 36%, white 40%, transparent 40%, transparent),
 radial-gradient(circle at 0    150%, $color_a1 24%, white 24%, white 28%, $color_a1 28%, $color_a1 36%, white 36%, white 40%, transparent 40%, transparent),
 radial-gradient(circle at 50%  100%, white 10%, $color_a1 10%, $color_a1 23%, white 23%, white 30%, $color_a1 30%, $color_a1 43%, white 43%, white 50%, $color_a1 50%, $color_a1 63%, white 63%, white 71%, transparent 71%, transparent),
 radial-gradient(circle at 100% 50%, white 5%, $color_a1 5%, $color_a1 15%, white 15%, white 20%, $color_a1 20%, $color_a1 29%, white 29%, white 34%, $color_a1 34%, $color_a1 44%, white 44%, white 49%, transparent 49%, transparent),
 radial-gradient(circle at 0    50%, white 5%, $color_a1 5%, $color_a1 15%, white 15%, white 20%, $color_a1 20%, $color_a1 29%, white 29%, white 34%, $color_a1 34%, $color_a1 44%, white 44%, white 49%, transparent 49%, transparent);
 background-size: 100px 50px;}
table.preprod>tbody:nth-child(even) { /* https://leaverou.github.io/css3patterns/#shippo */
 background-color:white;
 background-image: radial-gradient(closest-side, transparent 90%, rgba($color_a2,0.9) 90%),radial-gradient(closest-side, transparent 90%, rgba($color_a2,0.9) 90%);
 background-size:80px 80px;
 background-position:0 0, 40px 40px;}
table.prod>tbody:nth-child(odd)  { /* https://leaverou.github.io/css3patterns/#seigaiha */
 background-image:
 radial-gradient(circle at 100% 150%, $color_b1 24%, white 24%, white 28%, $color_b1 28%, $color_b1 36%, white 36%, white 40%, transparent 40%, transparent),
 radial-gradient(circle at 0    150%, $color_b1 24%, white 24%, white 28%, $color_b1 28%, $color_b1 36%, white 36%, white 40%, transparent 40%, transparent),
 radial-gradient(circle at 50%  100%, white 10%, $color_b1 10%, $color_b1 23%, white 23%, white 30%, $color_b1 30%, $color_b1 43%, white 43%, white 50%, $color_b1 50%, $color_b1 63%, white 63%, white 71%, transparent 71%, transparent),
 radial-gradient(circle at 100% 50%, white 5%, $color_b1 5%, $color_b1 15%, white 15%, white 20%, $color_b1 20%, $color_b1 29%, white 29%, white 34%, $color_b1 34%, $color_b1 44%, white 44%, white 49%, transparent 49%, transparent),
 radial-gradient(circle at 0    50%, white 5%, $color_b1 5%, $color_b1 15%, white 15%, white 20%, $color_b1 20%, $color_b1 29%, white 29%, white 34%, $color_b1 34%, $color_b1 44%, white 44%, white 49%, transparent 49%, transparent);
 background-size: 100px 50px;}
table.prod>tbody:nth-child(even) { /* https://leaverou.github.io/css3patterns/#shippo */
 background-color:white;
 background-image: radial-gradient(closest-side, transparent 90%, rgba($color_b2,0.9) 90%),radial-gradient(closest-side, transparent 90%, rgba($color_b2,0.9) 90%);
 background-size:80px 80px;
 background-position:0 0, 40px 40px;}
*:target,*:target>tr {background-color: rgba(250, 250, 100, 0.3) !important; transition: all 1s ease;}
@media print {
#toc {display:none;}
table.main>tbody>tr>td {vertical-align: top} 
table.main>thead {display: table-header-group;}
@page {margin:0.5cm}
}

</style>
<script>
function myFunction(id) {
    var body = document.body, range, sel;
	var el = document.getElementById(id)
    if (document.createRange && window.getSelection) {
        range = document.createRange();
        sel = window.getSelection();
        sel.removeAllRanges();
        try {
            range.selectNodeContents(el);
            sel.addRange(range);
        } catch (e) {
            range.selectNode(el);
            sel.addRange(range);
        }
        document.execCommand("copy");
    } else if (body.createTextRange) {
        range = body.createTextRange();
        range.moveToElementText(el);
        range.select();
        range.execCommand("Copy");
    }
	alert('Table copiée')
} 
</script>
</head>
<body>
"@
    $html ='<p>Extraction démarrée le {0} à  {1}, sur les données du portail indus par le compte caccia {2}.</p>' -f $runtime.date.ToString('dddd dd/MM/yyyy'), $runtime.date.ToString('HH:mm'),$user  
    Write-Output $html

    printHtmlKyssResult
    $html ='<p>Dans les secrets Kyss, les clés "{0}" sont systématiquement ignorées car elles étaient fournies par défaut.' -f $config.defaultlogin
    Write-Output $html
    write-output 'L''estimation de la qualité: la note devrait être la plus élevée possible, un mot de passe caccia score environ 16. La notation est très sensible à la longueur du mot de passe.'
    write-output 'Les hashés présentés sont issus du mot de passe et d''un sel par application pour masquer d''éventuels mots de passes communs à plusieurs applications.</p>'
    write-output '<p>Les secrets structurés sont des secrets CLE-VALEUR (KV) pour lesquels les clés suivantes prédéfinies doivent figurer. Le script accepte:'
    $html = '<ol><li>le motif <em>{0}</em> pour l''identifiant</li><li> le motif <em>{1}</em> pour le secret </li>' -f $config.prop_user, $config.prop_pass 
    Write-Output $html
    Write-Output '<li>le script tolère plusieurs match pour l''un des deux motifs mais pas pour les deux motifs en même temps</li></ol>'
    Write-Output 'Si le secret n''est pas reconnu en structuré, le script le traite comme non structuré avec la clé utilisée en identifiant et le hash de la valeur est présenté'
    Write-output 'Les secret mal structurés sont des secrets pour lesquels les attendus ne sont pas détectés totalement.</p>'
    $html = '<p>Idée originale de <a href="{0}" title="met à jour ta copie">PE Périllon</a></p>' -f $config.project_url 
    Write-Output $html 
    Write-Output "</body></html>"
}

function printHtmlKyssResult(){

    #create disposable empty result
    $html_empty_result = '<td class="noresult"></td>'
    $html_allempty_result = $html_empty_result * $RESULT['ENV'].count 

    Write-Output '<button onclick="myFunction(''report_data'')">Copier la table dans le presse-papier</button>'

    $html = '<table class="main {0}" id="report_data">'
    if ( $runtime.env -eq "HPROD" ){
         $html = $html -f "preprod"
    }else{
         $html = $html -f "prod"

    }
    Write-Output $html 

    write-output  @"
<thead>
    <tr><th>niveau 1</th><th>niveau 2</th><th>niveau 3</th><th>niveau 3+</th><th>Identifiant</th><th>Estimation qualité</th><th>Empreinte</th><th>date</th><th>Lien web</th><th>Status</th><th>Clé de réconciliation</th><th>Meta Données</th>
</tr></thead>
"@

    foreach ( $nna in $RESULT['NNA'].keys ){
        Write-Output '<tbody>'
        foreach ( $env in $RESULT['ENV'].keys ){
            foreach ( $team in $RESULT['TEAM'].keys ) {
                if ( $RESULT['SECRET'].ContainsKey($nna) ) {
                   if ($RESULT['SECRET'][$nna].Contains($env) ) {  
                       if (  $RESULT['SECRET'][$nna][$env].Contains($team) ) {                             
                            $keys = $RESULT['SECRET'][$nna][$env][$team].Keys
                            foreach ( $subt in $keys ){ 
                                $teamtree=buildTeamtree $team $subt 
                                printHtmlSecret $RESULT['SECRET'][$nna][$env][$team][$subt] $nna $env $team $teamtree
                            }
                            if ( $keys.count -eq 0 ){
                                printHtmlSecret $null $nna $env $team ""
                            }
                       } #if $team 
                   }#if env
                }#if nna 
            }#for all $team
        }#for all $env
        Write-Output "</tbody>"
    }#for all $nna 

    write-output @"
</table>
"@

}

function printHtmlSecret($answer, [string]$nna,[string]$env,[string]$team,[string]$teamtree ){
    $url =buildKyssLink $nna $env $teamtree 
    $pre_html = '<td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td>' -f $nna,$env,$team,$teamtree
    $anchor = '<a href="{0}" target="_blank">{1}</a>'
    if ( $runtime.do_reconciliation ){
        $rec_teamtree = computeReconciliation $nna $teamtree             
    }
    else {
        $rec_teamtree = 'désactivé'
    }

    if ( $null -eq $answer){
        $path=buildKyssPath $nna $env $teamtree
        $link = $anchor -f $url, $path        
        Write-Output '<tr class="noResult">'
        Write-Output $pre_html
        $html =         '<td></td>   <td></td>   <td></td>   <td></td>   <td>{0}</td><td>{1}</td><td>{2}</td>   <td></td></tr>' -f $link,"Absent",$rec_teamtree
        Write-Output $html
        
    }else{
         $link = $anchor -f $url, $answer['PATH']
         if ( $answer['COUNT'] -gt 0 ){
            $html_date = $answer['TS'].ToString($config.dateFormat,$null)
            $html_answer = [System.Web.HttpUtility]::HtmlEncode($answer['ANSWER'])
            $html_option = [System.Web.HttpUtility]::HtmlEncode($answer['OPT'])
            $rec_full = 'désactivé'
            foreach ( $k in $answer['PSSWD'].keys ){
                Write-Output '<tr>'
                Write-Output $pre_html
                $sign = $answer['PSSWD'][$k]
                if ( $runtime.do_reconciliation ){
                    $rec_login = computeReconciliation $nna $k 
                    $rec_full = $rec_teamtree +'::'+$rec_login
                }
                $html = '<td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td>{4}</td><td>{5}</td><td>{6}</td><td>{7}</td></tr>' -f [System.Web.HttpUtility]::HtmlEncode($k),$sign[0],$sign[1],$html_date,$link,$html_answer,[System.Web.HttpUtility]::HtmlEncode($rec_full),$html_option
                Write-Output $html

            }#foreach 
        }elseif ( $answer['COUNT'] -eq 0 ) {
                Write-Output '<tr class="emptyResult">'
                Write-Output $pre_html
                $html_date = $answer['TS'].ToString($config.dateFormat,$null)
                $html = '<td></td>   <td></td>   <td></td>   <td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td>   <td></td></tr>' -f $html_date,$link,'conteneur vide',$rec_teamtree 
                Write-Output $html 
        }else {
                Write-Output '<tr class="errorResult">'
                Write-Output $pre_html
                $html = '<td></td>   <td></td>   <td></td>   <td></td>   <td>{0}</td><td>{1}</td><td>{2}</td>   <td></td></tr>' -f $link,$answer['ANSWER'],$rec_teamtree
                Write-Output $html
        }
    }
}


function promptPassword([string] $username){
    $runtime.passwordAsked = $true 
    $text="Please enter caccia password for user "+$username 
    return Read-Host -assecurestring   $text
}

function purgeLocalFile([string] $passwd, [string]$crudefilePattern, [int] $ttl_days ){
    $filter = $crudefilePattern -replace '\[[A-Z]+\]','*'
    $ref = (Get-Date).AddDays(-$ttl_days)
    if ( $ttl_days -lt 1 ){
        Write-Host -NoNewline "purge désactivée pour "
    }
    else {
        Write-Host -NoNewline "purge à $ttl_days jours pour "
    }
    Write-host -ForegroundColor yellow $filter 
    Get-ChildItem -Path $passwd -Filter $filter | Where-Object { $_.CreationTime -lt $ref }| Remove-Item -Verbose  

}

#caccia password should be rated 16,2
function ratePassword ([string] $passwd ){
    if ( $passwd.Length -lt 5 ){
        return 0
    }
    $char=0
    if ( $passwd -match '[A-Z]' ){
        $char=$char+26
    }
    if ( $passwd -match '[a-z]' ){
        $char=$char+26
    }
    if ( $passwd -match '[0-9]' ){
        $char=$char+10
    }
    #pénaliser les lettres en doubles.
    $pass = $passwd.ToCharArray() | Select-Object -Unique
    $cnt = ($pass|Measure-Object).Count 
    $leng = [Math]::floor(($cnt + 3.0*$passwd.Length)/4)
    $pass = $passwd -replace "[a-zA-Z0-9]",""
    if ( $pass.Length -gt 0 ){
        $char=$char+( $pass.ToCharArray() | Select-Object -Unique | Measure-Object ).Count
    }
    return [Math]::round([Math]::Log10( [Math]::Pow($char, $leng )),1)

}

function renameFile($SourceFilePath){
    $DateNow = (Get-Item $SourceFilePath | Select-Object creationTime ).creationTime.ToString('yyyyMMdd_HHmmss')    
    $FileName = [io.path]::GetFileNameWithoutExtension($SourceFilePath) #Récupère le nom du fichier uniquement
    $FileExtension = [io.path]::GetExtension($SourceFilePath) #Récupère l'extension du fichier uniquement
    $Directory = [System.IO.Path]::GetDirectoryName($SourceFilePath);
    $newFileName="{0}.{1}-old{2}" -f $FileName, $DateNow,$FileExtension
    $target=[System.IO.Path]::Combine($Directory, $newFileName);
    if ( Test-Path $target ){
        Remove-Item -Path $target 
    }
    Write-Host -ForegroundColor Yellow "rename $SourceFilePath to $target"
    Rename-Item -Path $SourceFilePath -newname $target -ErrorAction SilentlyContinue  #Renommage du fichier
}

function storeResult( $nna, $folder, $anwer){
    $indexes = $folder.split('/',3)

    if ( $indexes.count -lt 2){
        return
    }
    $env = $indexes[0]
    $team= $indexes[1]
    
    if ( $indexes.count -eq 3 ){
        $subt= $indexes[2]
    }
    else {
        $subt = $config.nosubtree 
    }
    

    if ( $RESULT['SECRET'].Containskey($nna)){
            if ( $RESULT['SECRET'][$nna].contains($env) ){
                if ($RESULT['SECRET'][$nna][$env].contains($team)){
                    if ($RESULT['SECRET'][$nna][$env][$team].contains($subt) ){
                    #should never happend.
                    $RESULT['SECRET'][$nna][$env][$team][$subt]=$answer
                }else{
                    $RESULT['SECRET'][$nna][$env][$team].add($subt,$answer)  
                }
            }
            else{
                $RESULT['SECRET'][$nna][$env].add($team,[ordered]@{$subt=$answer})  
            }
        }
        else{
            $RESULT['SECRET'][$nna].add( $env,[ordered]@{$team=[ordered]@{$subt=$answer}}) 
        }
    }
    else {
        $tmp0 = [ordered]@{$subt=$answer}
        $tmp1 = [ordered]@{$team=$tmp0}
        $tmp2 = [ordered]@{$env=$tmp1}
        $RESULT['SECRET'].add( $nna,  $tmp2) 
    }

    if ( $RESULT['NNA'].Contains($nna)){
        $RESULT['NNA'][$nna]++| out-null 
    }
    else{
        $RESULT['NNA'].add($nna,1)| out-null 
    }
    if ( $RESULT['ENV'].ContainsKey($env)){
        $RESULT['ENV'][$env]++| out-null 
    }
    else{
        $RESULT['ENV'].add($env,1)| out-null 
    }

    if ( $RESULT['TEAM'].ContainsKey($team)){
        $RESULT['TEAM'][$team]++| out-null 
    }
    else{
        $RESULT['TEAM'].add($team,1)| out-null 
    }

}



function testNetworkAvailability(){
    $site =  $runtime.site  
    $port = $runtime.port 
    #en powershell 5 on ne peut aller tres loin...
    $it = 0 
    while ($true) {
        Write-Host -NoNewline "teste #$it la disponibilité du serveur $site "
        try {    
            Test-netConnection $site -port $port -ErrorAction Stop | Out-Null
            Write-Host -ForegroundColor Green "OK"
            Test-netConnection $site -port $port -ErrorAction Stop
            return 
        }catch{
            $myError = $_.Exception.Message
            Write-Host -ForegroundColor DarkYellow "Echec - vérifiez votre réseau" 
            Write-Host -ForegroundColor Red $myError 
        }
        $it++ 
        if ( $it -lt $config.network_try ){
            Write-Host "attente $it secondes..." 
            Start-Sleep -Seconds $it 
        }
        else {
            break
        }
    }
    exit $config.exitCode['NETWORK_FAILURE']
}

function vault-login ( [string] $user ,[string] $passwd ){
    $url =  $runtime.param_address +  $config.kyss_login.Replace('[LOGIN]',$user.ToUpper() )
    $data = @{"password"=$passwd} | ConvertTo-Json 
    
    try{
        $answer = Invoke-RestMethod $url -Method Post -Body $data -ContentType 'application/json' 
        $token = $answer.auth.client_token
        $runtime.credentialValid=$true

    }catch {
        $myError = $_.Exception.Message 
        $runtime.credentialValid=$false
        Write-Host -ForegroundColor Red "Failed authentication"
        Write-Error $myError
    }
    return $token
}


function vault-kvlist ( [string]$token,[string]$nna,[string]$tree ){


    $url =  $runtime.param_address + $config.kyss_kvlist.replace('[NNA]',$nna).Replace('[FULLTREE]',$tree )
    $headers = @{
        "X-Vault-Request"="true"
        "X-Vault-Token"="$token"   
    }

    $res = @{'COUNT'=-1;'ANSWER'=$false }
    
    try{
        $answer = Invoke-RestMethod $url -Method Get -Headers $headers -ContentType 'application/json' 
        $res['ANSWER'] = $answer.data.keys
        $res['COUNT']  = ($answer.data.keys|Measure-Object).count 

    }catch {
        $res['ANSWER'] = $_.Exception.Message 
        if ( $_.Exception.Response.StatusCode -eq "NotFound" ){
            #erreur de chemin
        }
        if  ( $_.Exception.Response.StatusCode -eq "Forbidden" ){
            #le tocken ne donne pas acces à cette ressource
        }
    }
    return $res
}



function vault-kvget ( [string]$token,[string]$nna,[string]$tree ){

    $url =  $runtime.param_address + $config.kyss_kvget.replace('[NNA]',$nna).Replace('[FULLTREE]',$tree )
    $headers = @{
        "X-Vault-Request"="true"
        "X-Vault-Token"="$token"   
    }
    
    try{
        $answer = Invoke-RestMethod $url -Method Get -Headers $headers -ContentType 'application/json' 

        $data = $answer.data.data
        $ts = [datetime]::Parse($answer.data.metadata.created_time)

        $res=parse-secret $data $ts $nna $tree 
    }catch {
        $myError = $_.Exception.Message 
        $res = init-result $nna $tree 
        $res['ANSWER'] = $myError 
        if ( $_.Exception.Response.StatusCode -eq "NotFound" ){
            #erreur de chemin
        }
        if  ( $_.Exception.Response.StatusCode -eq "Forbidden" ){
            #le tocken ne donne pas acces à cette ressource
        }
    }
    return $res
}





#https://hprod.kyss.local/v1/sys/internal/ui/mounts
function vault-mount([string]$token ){
    $url =  $runtime.param_address + $config.kyss_mount
    $headers = @{
        "X-Vault-Request"="true"
        "X-Vault-Token"="$token"   
    }    
    $answer = Invoke-RestMethod $url -Method Get -Headers $headers -ContentType 'application/json' 
    $data=$answer.data.secret 
    return Get-Member -InputObject $data -MemberType NoteProperty | Select-Object -ExpandProperty Name | 
        Where-Object { $_ -notin $config.bypassedSecret }
}

function vault-recursive([string] $token, [string]$nna , [string]$folder ){
    if ( $folder.endsWith('/')){
        if ( $folder.Startswith("/") ){
            $folder=$folder.substring(1)
        }
        $answer = vault-kvlist $token   $nna  $folder
        if ( $answer['COUNT'] -gt 0 ){
            foreach ( $key in $answer['ANSWER'] ){
                $path = $folder+$key
                vault-recursive  $token $nna $path
            
            }#foreach
        }
    }else {
        $answer = vault-kvget $token $nna $folder 
        storeResult $nna $folder $answer 
    }
} 

function main( ){

    ### gestion de l'input
    if ( $runtime.do_extract_all ){
        Write-Host "Utilisation du flag -extract_all, fichier de configuration ignoré"
    }
    else{
        try{
            $myconf = findLocalFile $runtime.cwd $runtime.confile 
            Write-Host -NoNewline "Utilisation du fichier $myconf "
            $runtime.roots = Get-Content $myconf 
            Write-Host -ForegroundColor Green "OK"
        }catch{
            $myError = $_.Exception.Message
            Write-Host -ForegroundColor red "Erreur de fichier de configuration"
            Write-Host $myError
            exit $config.exitCode['NO_CONFIG']
        }
    }


    ### gestion de l'output
    $reportPath=buildReportPath 
    $outfile = buildReportFileName $reportPath $runtime.env $runtime.date $runtime.reportTag 

    ### gestion de l'utilisateur 
    if ([string]::IsNullOrWhiteSpace($runtime.username )){
        $username = getSytemUser 
    }
    else {
        $username = $runtime.username 
    }

    Write-Host -NoNewline "Utilisateur sesame: "
    Write-Host -ForegroundColor Green $username 

    $password_file = [System.IO.Path]::Combine( $runtime.cwd , $username + $config.passwordStoreExt )    
    $runtime.credentialValid = $false

    $secure_password=$null 
    if (  (test-path $password_file ) -and $runtime.do_pass_store ){
        try {
            $secure_password = Get-Content $password_file | ConvertTo-SecureString 
            $secure_password.MakeReadOnly()
            $runtime.credentialValid = $true

        }
        catch {
            $myError = $_.Exception.Message
            Write-Host -BackgroundColor DarkRed -ForegroundColor White "Ne peux pas utiliser le mot de passe en cache "
            Write-Host -ForegroundColor Red $myError 
        }
    }


    if ( $runtime.do_pass_ask ){
        if ( [string]::IsNullOrEmpty($secure_password)){
            $secure_password = promptPassword $username 
            $runtime.credentialValid = $true
        }
        else {
            Write-Host "utilisation du mot de passe en cache"
        }
    }



    if ( $runtime.credentialValid ){
        $clear_password=[System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure_password))
    }
    else{
        Write-Host -ForegroundColor red "Pas de mot de passe disponible, abandon."
        exit $config.exitCode['NO_PASSWORD']
    }


    ###verif réseau, c'est con mais c'est une raison pour
    testNetworkAvailability

    $token = vault-login $username $clear_password


    ### sauvegarde du mot de passe si il a marché 
    Write-Host -NoNewline "Gestion mot de passe "
    if ($runtime.do_pass_store ){
        if ( $runtime.credentialValid ){
            if ( $runtime.passwordAsked ){
                $secure_password | ConvertFrom-SecureString | Out-File $password_file 
                Write-Host -ForegroundColor green "création"
            } else {
                Write-Host -ForegroundColor green "ras"
            }
        }else {
            #enfin on dégomme le mot de passe stocké s'il n'a pas marché.
            if (-not ($runtime.passwordAsked) -and (Test-Path $password_file) ){
                renameFile $password_file 
                Write-Host -ForegroundColor Green "suppression"
            }
            exit $config.exitCode['FAILED_AUTHENTICATION']
        }
    }#if do_pass_store
   

    if ( $runtime.do_extract_all ){ 
        Write-Host -NoNewline "récuperation des racines de chemins "
        Try {
            $secrets = vault-mount $token
            $count =( $secrets|Measure-Object).count 
            Write-Host -ForegroundColor Green "$count OK"
            $runtime.roots = $secrets | Sort-Object
        }catch{
            $myError = $_.Exception.Message
            Write-Output $myError 
        }
    }



    foreach ( $it in $runtime.roots ){
        Write-Host -ForegroundColor Yellow "traitement de $it ..."
        $indexes=$it.trim().split('/',3)
        if ( $indexes.count -ge 2 ){
            $nna = $indexes[1]
            if ( $indexes.count -eq 3 ){
                $tree = $indexes[2]
            }else{
                $tree = "/"
            }
            if ( [string]::IsNullOrEmpty($tree)){
                $tree="/"
            }
            vault-recursive $token $nna $tree 
         }
         #sinon je peux pas adresser la bonne partition de secret
    }

    Write-Host "Fin de l'extraction, génération du rapport"

    if ( $runtime.do_reconciliation ){
        Write-Host -NoNewline "Réconciliation des clés activées "
        foreach( $nna in $RESULT['NNA'].keys ){
            loadReconcilationFile $nna 
        }
        Write-Host -ForegroundColor Green "OK"
    }


    printHtmlReport $username | Out-File  -FilePath  $outfile

    if ($runtime.do_open_report ){
        Invoke-Item $outfile
    }

    exit $config.exitCode['SUCCESS']
 }

##############################
##############################

$RECONCILIATION=@{}

$RESULT =@{
'ENV'=@{}
'NNA'=[ordered]@{}
'TEAM'=@{}
'SECRET'=@{}
}

if ( $environnement -eq 'PROD'){
    $runtime.param_address = $config.url_PROD 
    $runtime.env = 'PROD'
    $runtime.site = $config.site_PROD
}
elseif ( $environnement -eq 'HPRD' ){
    $runtime.param_address = $config.url_HPRD
    $runtime.env = 'HPRD'
    $runtime.site = $config.site_HPRD
}
elseif ( $environnement -eq 'METIER'){
    $runtime.param_address = $config.url_HPME
    $runtime.env = 'HPRD'
    $runtime.site = $config.site_HPME
}
else{
    Write-Host "Erreur $environnement"
}



main 


