#-------------------------------------------------------------#
#----Initial Declarations-------------------------------------#
#-------------------------------------------------------------#
#region
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase

$ControlsHash = [HashTable]::Synchronized(@{})

$ControlsHash.Xaml = @"
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
#----Event Handlers-------------------------------------------#
#-------------------------------------------------------------#
#region

# TO-DO: Remove runspace when script execution ends
# $Runspace.Add_StateChanged({})

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
    $Runspace.SessionStateProxy.SetVariable('ControlsHash', $ControlsHash)

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
#endregion


#-------------------------------------------------------------#
#----Script Execution-----------------------------------------#
#-------------------------------------------------------------#
#region
$ControlsHash.NewRunspace   = ${Function:New-Runspace}
$ControlsHash.StartRunspace = ${Function:Start-Runspace}

$ConsoleScript = {
    $WindowScript = {
        $ControlsHash.Window = [Windows.Markup.XamlReader]::Parse($ControlsHash.Xaml)

        $Elements = ([Xml]$ControlsHash.Xaml).GetElementsByTagName('*')

        ForEach($Element in $Elements)
        {
            $Control = $ControlsHash.Window.FindName($Element.Name)
            If($Control) { $ControlsHash.Add($Control.Name, $Control) }
        }
    }

    # Add user events inside this script block
    $EventScript = {        
        Function Update-TextBox([String]$UpdateText)
        {
            $ControlsHash.TextBox.Dispatcher.Invoke({
                $ControlsHash.TextBox.AppendText($UpdateText)
            })
        }
        
        $ControlsHash.UpdateTextBox = ${Function:Update-TextBox}

        $ControlsHash.Button.Add_Click(
        {
            $this.IsEnabled = $False

            &$ControlsHash.UpdateTextBox("Click!`n")
            Start-Sleep 5

            $this.IsEnabled = $True
        })
    }

    # Dedicated runspace and thread for GUI window
    $WindowRunspace = & $ControlsHash.NewRunspace
    $WindowThread = & $ControlsHash.StartRunspace $WindowRunspace $WindowScript
    $WindowThread.Invoke()

    # Dedicated runspace and thread for GUI control events
    $EventRunspace = &$ControlsHash.NewRunspace
    $EventThread = & $ControlsHash.StartRunspace $EventRunspace $EventScript
    $EventThread.Invoke()

    # Repurpose WindowThread since it owns the Window object
    $WindowThread.Commands.Clear()
    [Void]$WindowThread.AddScript({ [Void]$ControlsHash.Window.ShowDialog() })

    # Invoke Asynchronously
    $WindowStatus = $WindowThread.BeginInvoke()
    Do {<#Nothing#>} Until ($WindowStatus.IsCompleted)
    $WindowStatus = $WindowThread.EndInvoke($WindowStatus)

    # Clean up runspaces
    $AllRunspaces = Get-Variable -Name *Runspace

    ForEach($Runspace in $AllRunspaces)
    {
        $Runspace.Value.Close()
        $Runspace.Value.Dispose()
    }
}

# Dedicated runspace and thread for console host
$ConsoleRunspace = & $ControlsHash.NewRunspace
$ConsoleThread = & $ControlsHash.StartRunspace $ConsoleRunspace $ConsoleScript

# Invoke Asynchronously
$ConsoleStatus = $ConsoleThread.BeginInvoke()
Do { <#Nothing#> } Until ($ConsoleStatus.IsCompleted)
$ConsoleStatus = $ConsoleThread.EndInvoke($ConsoleStatus)

# Remove-Variable ControlsHash, *Runspace, *Script, *Status, *Thread
#endregion