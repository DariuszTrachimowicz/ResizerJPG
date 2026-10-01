Add-Type -AssemblyName PresentationCore,WindowsBase
if (-not ('ResizerPhoto' -as [type])) {
    Add-Type -ReferencedAssemblies @('System.dll', [Windows.Media.ImageSource].Assembly.Location, [Windows.DependencyObject].Assembly.Location) -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Windows.Media;

public sealed class ResizerPhoto : INotifyPropertyChanged
{
    public string FullPath { get; set; }
    public string SourceRoot { get; set; }
    public string SourcePath { get; set; }
    public string SourceName { get; set; }
    public string RelativePath { get; set; }
    public string Name { get; set; }
    public string Orientation { get; set; }
    public int OriginalWidth { get; set; }
    public int OriginalHeight { get; set; }
    public string Error { get; set; }
    private bool included = true;
    private ImageSource thumbnail;
    private string details = "";
    private string status = "";
    private string output = "";
    public bool IsIncluded
    {
        get { return included; }
        set { if (included != value) { included = value; Notify("IsIncluded"); } }
    }
    public ImageSource Thumbnail
    {
        get { return thumbnail; }
        set { if (thumbnail != value) { thumbnail = value; Notify("Thumbnail"); } }
    }
    public string Details
    {
        get { return details; }
        set { if (details != value) { details = value; Notify("Details"); } }
    }
    public string Status
    {
        get { return status; }
        set { if (status != value) { status = value; Notify("Status"); } }
    }
    public string LastOutputPath
    {
        get { return output; }
        set { if (output != value) { output = value; Notify("LastOutputPath"); } }
    }
    public event PropertyChangedEventHandler PropertyChanged;
    private void Notify(string property)
    {
        var handler = PropertyChanged;
        if (handler != null) { handler(this, new PropertyChangedEventArgs(property)); }
    }
}
'@
}
