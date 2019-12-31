#-------------------------------------------------------------#
#----Initial Declarations-------------------------------------#
#-------------------------------------------------------------#
#region

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$Global:SyncHash = [HashTable]::Synchronized(@{})

$SyncHash.Xaml = @"
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
        xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
        xmlns:local="clr-namespace:XamlGenerator"
        mc:Ignorable="d"
        Title="MainWindow" SizeToContent="WidthAndHeight">
    <StackPanel x:Name="StackPanel" Height="450" Width="800">
        <TextBox x:Name="TextBox" Height="350" Margin="10,10,10,0" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" VerticalAlignment="Bottom"/>
        <ProgressBar x:Name="ProgressBar" Height="20" Margin="10,10,10,0" VerticalAlignment="Bottom"/>
        <Button x:Name="Button" Content="Test UI" HorizontalAlignment="Left" VerticalAlignment="Bottom" Margin="10"/>
    </StackPanel>
</Window>
"@

#endregion

#-------------------------------------------------------------#
#----Utility Functions----------------------------------------#
#-------------------------------------------------------------#
#region

Function New-Runspace
{
    $Runspace = [RunspaceFactory]::CreateRunspace($Host)
    $Runspace.ApartmentState = 'STA'
    $Runspace.ThreadOptions  = 'ReuseThread'
    $Runspace.Open()
    $Runspace.SessionStateProxy.SetVariable('SyncHash', $SyncHash)

    Return $Runspace
}

Function Start-Runspace
{
    [CmdletBinding()]
    Param([Parameter(Mandatory=$True,Position=0)]$Runspace,
          [Parameter(Mandatory=$True,Position=1)]$ScriptBlock)

    $Thread = [PowerShell]::Create('NewRunspace').AddScript($ScriptBlock)
    $Thread.Runspace = $Runspace
    
    Return $Thread
}

Function Update-Control
{
    [CmdletBinding()]
    Param([Parameter(Mandatory=$True,Position=0)][String]$Name,
          [Parameter(Mandatory=$True,Position=1)][ScriptBlock]$ScriptBlock)

    $Control = $SyncHash[$Name]    
    If($Control) { $Control.Dispatcher.Invoke($ScriptBlock) }
}

$SyncHash.NewRunspace   = ${Function:New-Runspace}
$SyncHash.StartRunspace = ${Function:Start-Runspace}
$SyncHash.UpdateControl = ${Function:Update-Control}

#endregion

#-------------------------------------------------------------#
#----Script Execution-----------------------------------------#
#-------------------------------------------------------------#
#region

$WindowScript = {
    $SyncHash.Window = [Windows.Markup.XamlReader]::Parse($SyncHash.Xaml)

    $Elements = ([Xml]$SyncHash.Xaml).GetElementsByTagName('*')

    ForEach($Element in $Elements)
    {
        $Control = $SyncHash.Window.FindName($Element.Name)
        If($Control) { $SyncHash.Add($Control.Name, $Control) }
    }

    #region Background runspace to clean up jobs
    $Script:JobCleanup = [HashTable]::Synchronized(@{})
    $Script:Jobs = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))

    $JobCleanup.Flag = $True
    $JobsRunspace =[RunspaceFactory]::CreateRunspace()
    $JobsRunspace.ApartmentState = "STA"
    $JobsRunspace.ThreadOptions = "ReuseThread"          
    $JobsRunspace.Open()        
    $JobsRunspace.SessionStateProxy.SetVariable("JobCleanup", $JobCleanup)     
    $JobsRunspace.SessionStateProxy.SetVariable("Jobs", $Jobs) 

    $JobCleanup.PowerShell = [PowerShell]::Create().AddScript({
        #Routine to handle completed runspaces
        Do {    
            Foreach($Runspace in $Jobs) {            
                If ($Runspace.Runspace.IsCompleted) {
                    [Void]$Runspace.Powershell.EndInvoke($Runspace.Runspace)
                    $Runspace.Powershell.Dispose()
                    $Runspace.Runspace = $null
                    $Runspace.Powershell = $null               
                } 
            }
            #Clean out unused runspace jobs
            $TempHash = $Jobs.Clone()
            $TempHash.Where{ $_.Runspace -eq $Null }.ForEach{ $Jobs.Remove($_) }
            Start-Sleep -Seconds 1     
        } While ($JobCleanup.Flag)
    })

    $JobCleanup.PowerShell.Runspace = $JobsRunspace
    $JobCleanup.Thread = $JobCleanup.PowerShell.BeginInvoke()  
    #endregion Background runspace to clean up jobs

    $SyncHash.Button.Add_Click({
        $ButtonScript = {
            & $SyncHash.UpdateControl TextBox { $SyncHash.TextBox.AppendText("Populating list...") }

            $FileList = Get-ChildItem $env:USERPROFILE\Documents -File -Recurse

            & $SyncHash.UpdateControl ProgressBar {
                write-host $FileList.Count
                $SyncHash.ProgressBar.Value   = 0
                $SyncHash.ProgressBar.Minimum = 0
                $SyncHash.ProgressBar.Maximum = $FileList.Count
            }

            & $SyncHash.UpdateControl TextBox { $SyncHash.TextBox.AppendText("Done!`n") }

            For($i = 0 ; $i -lt $FileList.Count ; $i++)
            {
                & $SyncHash.UpdateControl ProgressBar { $SyncHash.ProgressBar.Value = $i }
                & $SyncHash.UpdateControl TextBox { $SyncHash.TextBox.AppendText("$($FileList[$i])`n") }
            }
        }

        $ButtonRunspace = & $SyncHash.NewRunspace
        $ButtonThread   = & $SyncHash.StartRunspace $ButtonRunspace $ButtonScript

        [Void]$Jobs.Add((
            [PSCustomObject]@{
                PowerShell = $ButtonThread
                Runspace = $ButtonThread.BeginInvoke()
            }
        ))
    })

    #region Window Close 
    $SyncHash.Window.Add_Closed({
        Write-Verbose 'Halt runspace cleanup job processing'
        $JobCleanup.Flag = $False

        #Stop all runspaces
        $JobCleanup.PowerShell.Dispose()      
    })
    #endregion Window Close 
    #endregion Boe's Additions

    #$x.Host.Runspace.Events.GenerateEvent( "TestClicked", $x.test, $null, "test event")

    #$SyncHash.Window.Activate()
    [Void]$SyncHash.Window.ShowDialog()
    $SyncHash.Error = $Error
}

$WindowRunspace = & $SyncHash.NewRunspace
$WindowThread = & $SyncHash.StartRunspace $WindowRunspace $WindowScript

$Data = $WindowThread.BeginInvoke()

#endregion