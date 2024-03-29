cls

###############################################################################################
#################### Script para Monitoramento das filas do DFS ###############################
###############################################################################################
######################################### VARIAVEIS ###########################################
###############################################################################################
############ $ExclusionServers = Servidores que deverão ser ignorados nos testes ##############
############### $LimitError = A quantidade de erros de conexão que é aceitavel ################
## $LimitBacklog = O limite aceitavel de backlog de arquivos na soma de todas as replicações ##
###############################################################################################

# Executar o comando abaixoy para criar o Source e ser possivel gravar as informações em log
# New-EventLog -Logname Application -Source "Monitoramento DFSR"

$caminho = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
$doc = New-Object System.Xml.XmlDocument
$doc.Load("$caminho\ConfigMonitorAllDFS.xml")
[System.Xml.XmlElement]$Config = $doc.DocumentElement

$ExclusionServers = @("Host Excluido 1", "Host Excluido 2",)
$LimitError = $Config.DFSR.LimitError
$LimitBacklog = $Config.DFSR.LimitBacklog

$CountError = 0
$SumBacklog = 0

#Variáveis utilizadas pelo Zabbix

$returnStateOK = 0
$returnStateWarning = 1
$returnStateCritical = 2
$returnStateUnknown = 3
$status = $returnStateUnknown
$nscaOut = ""
$Result = ""


$DFSRConnection = Get-DfsrConnection 



ForEach ($replication in $DFSRConnection){

	$GroupName = $replication.GroupName
 
	$ReplicatedFolders = (Get-DfsReplicatedFolder $GroupName).Foldername
	$DestinationComputer = $replication.DestinationComputerName
	$SourceComputer = $replication.SourceComputerName
	$RepEnabled = $replication.Enabled
	
	if ($RepEnabled -eq "True"){
	
		ForEach ($ReplicatedFolder in $ReplicatedFolders){
		
		if ($ExclusionServers -contains $DestinationComputer -or $ExclusionServers -contains $SourceComputer){
			continue
		}
        
		
		$BacklogResult = dfsrdiag backlog /rgname:$GroupName /rfname:$ReplicatedFolder /smem:$SourceComputer /rmem:$DestinationComputer
				if ($BacklogResult -like "*ERROR*"){
			#Aguarda e Testa Novamente
			Start-Sleep -s 10
			$BacklogResult = dfsrdiag backlog /rgname:$GroupName /rfname:$ReplicatedFolder /smem:$SourceComputer /rmem:$DestinationComputer
			
			if ($BacklogResult -like "*ERROR*"){
				$dt = Get-Date -Format "yyyy:dd:MM hh:mm:ss"
				$Result += $dt+" "+$SourceComputer+"->"+$DestinationComputer +" - Pasta "+$ReplicatedFolder+" - Grupo "+$GroupName+" - ERRO CONSULTA`r`n"
				$CountError++
				continue
			}
		}
	
		$SplitedResult = $BacklogResult -split ": "
		
		if ($SplitedResult[2] -ne $null){
			$Backlog = [int]$SplitedResult[2]
			$SumBacklog = $SumBacklog + $Backlog
			$dt = Get-Date -Format "yyyy:dd:MM hh:mm:ss"
			$Result += $dt+" "+$SourceComputer+"->"+$DestinationComputer +" - Pasta "+$ReplicatedFolder+" - Grupo "+$GroupName+" - Backlog "+$Backlog+"`r`n"
		}else{
			$Backlog = 0
			$dt = Get-Date -Format "yyyy:dd:MM hh:mm:ss"
			$Result += $dt+" "+$SourceComputer+"->"+$DestinationComputer +" - Pasta "+$ReplicatedFolder+" - Grupo "+$GroupName+" - Backlog "+$Backlog+"`r`n"

		}
	}
	}else{
		$dt = Get-Date -Format "yyyy:dd:MM hh:mm:ss"
		$Result += $dt+" "+$SourceComputer+"->"+$DestinationComputer +" - Pasta "+$ReplicatedFolder+" - Grupo "+$GroupName+" - ###### DESABILITADA ######`r`n"
	}
}

#linhas para tratar os alertas por tempo alem do limite de arquivos na fila

$Hoje = Get-Date
if (($SumBacklog -ge $LimitBacklog) -and ($Config.alerta.data -eq "")){
	$Config.alerta.data = $Hoje.tostring("dd/MM/yyyy HH:mm:ss")
	$doc.Save("$caminho\ConfigMonitorAllDFS.xml")
}elseif($SumBacklog -lt $LimitBacklog){
	$Config.alerta.data = ""
	$doc.Save("$caminho\ConfigMonitorAllDFS.xml")
}


#linhas para tratar os alertas por tempo alem do limite de erros arquivos

$Hoje = Get-Date
if (($CountError -ge $LimitError ) -and ($Config.alertaErro.data -eq "")){
	$Config.alertaErro.data = $Hoje.tostring("dd/MM/yyyy HH:mm:ss")
	$doc.Save("$caminho\ConfigMonitorAllDFS.xml")
}
elseif($CountError -lt $LimitError){
	$Config.alertaErro.data = ""
	$doc.Save("$caminho\ConfigMonitorAllDFS.xml")
}



$Result +=  "Total Backlog: "+$SumBacklog+"`r`n"
&  "C:\Progra~1\Zabbix Agent\zabbix_sender.exe" -z svp03200monit01 -s svp03000arq01 -k backlog.list -o $SumBacklog
$Result +=  "Total Erros Conexao: "+$CountError+"`r`n"

$nscaOut +=  "Total Backlog: "+$SumBacklog+"\n"
$nscaOut +=  "Total Erros Conexao: "+$CountError+"\n"
$nscaOut +=  "Verifique os detalhes no log no Visualizador de Eventos em:\n"
$nscaOut += "$caminho\LOGDFSR.LOG"






$nscaOut = $nscaOut -Replace "`n", "\n"

$Result > "$caminho\LOGDFSR.LOG"

#tratamentos para o tempo de erro está maior que o definido
$dateErro = $config.alertaerro.data

if ($dateErro -eq ""){
$DataALvoErro = Get-Date
$DataALvoErro = $DataALvoErro.AddYears(10)
}else{
$dataErro = [DateTime]::ParseExact($dateErro,"dd/MM/yyyy HH:mm:ss",[System.Globalization.CultureInfo]::InvariantCulture)
$janelaMinutosErro = $config.alertaErro.limiteTempo
$DataALvoErro = $dataErro.Addminutes($janelaMinutosErro )
}
if (($CountError -ge $LimitError) -and ($hoje -gt $DataALvoErro))  {
		
#		Write-Host "Saiu no Critico"
		$status = $returnStateCritical
		&  "C:\Progra~1\Zabbix Agent\zabbix_sender.exe" -z svp03200monit01 -s svp03000arq01 -k dfsr.state -o 2
        Echo "$status"
		exit $status
		
}


#tratamentos para o tempo em que a fila está maior
$dateTm = $config.alerta.data

if ($dateTm -eq ""){
$DataALvo = Get-Date
$DataALvo = $DataALvo.AddYears(10)
}else{
$dataAlerta = [DateTime]::ParseExact($dateTm,"dd/MM/yyyy HH:mm:ss",[System.Globalization.CultureInfo]::InvariantCulture)
$janelaMinutos = $config.alerta.limiteTempo
$DataALvo = $dataAlerta.Addminutes($janelaMinutos )
}
if (($SumBacklog -ge $LimitBacklog)-and ($hoje -gt $DataALvo)){
#	Write-Host "Saiu no Critico"
		$status = $returnStateCritical
		&  "C:\Progra~1\Zabbix Agent\zabbix_sender.exe" -z svp03200monit01 -s svp03000arq01 -k dfsr.state -o 2
        Echo "$status"
		exit $status
}

#Saidas Warning

if ($CountError -gt 0){
#		Write-Host "Saiu no Warning"
		$status = $returnStateWarning
		&  "C:\Progra~1\Zabbix Agent\zabbix_sender.exe" -z svp03200monit01 -s svp03000arq01 -k dfsr.state -o 1
        Echo "$status"
	}


#Saida OK
#Write-Host "Saiu no OK"
$status = $returnStateOK
&  "C:\Progra~1\Zabbix Agent\zabbix_sender.exe" -z svp03200monit01 -s svp03000arq01 -k dfsr.state -o 0
Echo "$status"
exit $status
