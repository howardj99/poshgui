#-------------------------------------------------------------#
#----Initial Declarations-------------------------------------#
#-------------------------------------------------------------#
#region

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$Global:SyncHash = [HashTable]::Synchronized(@{})

$Xaml = @"
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

# Sample code for encoding/decoding strings; possible cleaner implementation
$EncodedXaml = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Xaml))
$XamlBytes   = [Convert]::FromBase64String($EncodedXaml)
$DecodedXaml = [Text.Encoding]::UTF8.GetString($XamlBytes, 0, $XamlBytes.Length)

#endregion

#-------------------------------------------------------------#
#----Utility Functions----------------------------------------#
#-------------------------------------------------------------#
#region

Function Start-RunspaceTask
{
    [CmdletBinding()]
    Param([Parameter(Mandatory=$True,Position=0)][ScriptBlock]$ScriptBlock,
          [Parameter(Mandatory=$True,Position=1)][PSObject[]]$ProxyVars)

    $Runspace = [RunspaceFactory]::CreateRunspace($Host)
    $Runspace.ApartmentState = 'STA'
    $Runspace.ThreadOptions  = 'ReuseThread'
    $Runspace.Open()

    ForEach($Var in $ProxyVars)
    {
        $Runspace.SessionStateProxy.SetVariable($Var.Name, $Var.Variable)
    }

    $Thread = [PowerShell]::Create('NewRunspace').AddScript($ScriptBlock)
    $Thread.Runspace = $Runspace
    
    [Void]$Jobs.Add([PSObject]@{ PowerShell = $Thread ; Runspace = $Thread.BeginInvoke() })
}

Function Update-Control
{
    [CmdletBinding()]
    Param([Parameter(Mandatory=$True,Position=0)][System.Windows.Controls.Control]$Control,
          [Parameter(Mandatory=$True,Position=1)][ScriptBlock]$ScriptBlock)

    $Control.Dispatcher.Invoke($ScriptBlock, 'Normal')
}

$SyncHash.StartRunspaceTask = ${Function:Start-RunspaceTask}
$SyncHash.UpdateControl     = ${Function:Update-Control}

#endregion

#-------------------------------------------------------------#
#----Runspace Cleanup Subroutine------------------------------#
#-------------------------------------------------------------#
#region

# Background runspace to clean up jobs (credit to Boe Prox PoshRSJob module and FoxDeploy)
$Jobs = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

$JobCleanupScript = {
    # Routine to handle completed runspaces
    Do
    {    
        ForEach($Job in $Jobs)
        {            
            If($Job.Runspace.IsCompleted)
            {
                [Void]$Job.Powershell.EndInvoke($Job.Runspace)
                $Job.PowerShell.Runspace.Close()
                $Job.PowerShell.Runspace.Dispose()
                $Runspace.Powershell.Dispose()
                
                $Jobs.Remove($Runspace)
            }
        }

        Start-Sleep -Seconds 1
    }
    While ($SyncHash.CleanupJobs)
}

Start-RunspaceTask $JobCleanupScript @([PSObject]@{ Name='Jobs' ; Variable=$Jobs })

#endregion

#-------------------------------------------------------------#
#----Control Event Handlers-----------------------------------#
#-------------------------------------------------------------#
#region

$Button_Click = {
    $SyncHash.TextBox.AppendText('Populating list...')

    $SyncHash.FileList = Get-ChildItem $env:USERPROFILE'\Documents\Code Projects' -File -Recurse -ErrorAction SilentlyContinue

    $SyncHash.TextBox.AppendText('Done!')

    $SyncHash.ProgressBar.Maximum  = $SyncHash.FileList.Count
    $SyncHash.ProgressBar.Minimum  = 0
    $SyncHash.ProgressBar.Value    = 0

    & $SyncHash.StartRunspaceTask {
        For($i = 1 ; $i -le $SyncHash.FileList.Count ; $i++)
        {
            & $SyncHash.UpdateControl $SyncHash.Window {
                $SyncHash.TextBox.AppendText("`n$($SyncHash.FileList[$i].FullName)")
                $SyncHash.ProgressBar.Value = $i
            }
        }
    } ([PSObject]@{ Name='SyncHash' ; Variable=$SyncHash })
}

#endregion

#-------------------------------------------------------------#
#----Script Execution-----------------------------------------#
#-------------------------------------------------------------#
#region

$SyncHash.Window = [Windows.Markup.XamlReader]::Parse($Xaml)

$Elements = ([Xml]$Xaml).GetElementsByTagName('*')

ForEach($Element in $Elements)
{
    $Control = $SyncHash.Window.FindName($Element.Name)
    If($Control) { $SyncHash.Add($Control.Name, $Control) }
}

#region Each event that user specifies goes here, grouped by UI control

$SyncHash.Button.Add_Click($Button_Click)

#endregion

$SyncHash.Window.Add_Closed({
    Write-Verbose 'Halt runspace cleanup job processing'
    $SyncHash.CleanupJobs = $False
})

# Begin job cleanup subroutine
$SyncHash.CleanupJobs = $True

[Void]$SyncHash.Window.ShowDialog()
$SyncHash.Error = $Error

#endregion