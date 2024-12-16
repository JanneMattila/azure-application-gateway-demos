<%@ Page Language="C#" %>
<html>
<head runat="server">
    <title>Probe</title>
</head>

<body>
    <% 
    try 
    { 
        if (System.IO.File.Exists(@"\maintenance.txt")) 
        { 
            Response.StatusCode=503; 
        } 
    } 
    catch (Exception) 
    {
        
    } %>
</body>
</html>