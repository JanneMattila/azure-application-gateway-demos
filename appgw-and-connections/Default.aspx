<%@ Page Language="C#" %>

<!DOCTYPE html>

<html xmlns="http://www.w3.org/1999/xhtml">

<head runat="server">
    <title>App</title>
    <!-- meta refresh every second: -->
    <meta http-equiv="refresh" content="1" />
</head>

<body>
    <form id="form1" runat="server">
        <div>
            <% Session["Counter"]=Convert.ToInt32(Session["Counter"]) + 1; %>

                Server:<br />
                <%= Server.MachineName + ":" + Request.Url.Port %><br />
                    Count:<br />
                    <%= Session["Counter"] %>
        </div>
    </form>
</body>

</html>