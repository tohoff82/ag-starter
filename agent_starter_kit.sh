#!/usr/bin/env bash

set -euo pipefail

# Usage: agent name is the only required parameter
if [[ $# -eq 0 || ${1-} == "-h" || ${1-} == "--help" ]]; then
    cat <<USAGE
Usage: $(basename "$0") <agent-name>

Creates a new .NET Aspire agent solution with the following structure in the CURRENT directory:
    <cwd>/
        - src.sln
        - <agent>.Agent (aspire apphost)
        - <agent>.Agent.Cqrs (classlib)
        - <agent>.Y.Core (servicedefaults)
        - <agent>.Api.Endpoints (webapi)
        - <agent>.Mcp.Endpoints (webapi)
        - <agent>.Web.Endpoints (web)

Notes:
    - Solution name is fixed to 'src'.
    - All projects are created as sibling folders in the current directory.
    - currentdir is derived from the directory this script is executed in.
USAGE
    exit 0
fi

# Input (single parameter)
agentname="$1"

# Derived constants/variables
slnname="src"                      # solution name fixed to 'src'
currentdir="$(basename "${PWD}")"  # using the directory where script is executed
basepath="${PWD}"                   # generate everything in current folder
dbname="$(echo "${agentname}" | tr '[:upper:]' '[:lower:]')"

echo "Agent name: ${agentname}"
echo "Current dir: ${currentdir}"
echo "Base path: ${basepath}"

# Check .NET version (require 9.0.0+)
dotnet_version=$(dotnet --version)
required_version="9.0.0"
if [[ "$(printf '%s\n' "$required_version" "$dotnet_version" | sort -V | head -n1)" != "$required_version" ]]; then
    echo "Error: .NET ${required_version} or higher is required."
    echo "Current version: ${dotnet_version}"
    echo "Please upgrade .NET before running this script."
    exit 1
fi

# Check if the required Aspire templates are installed
echo "Checking if .NET Aspire templates are installed..."
aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")

if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
    echo "Installing .NET Aspire templates..."
    dotnet workload install aspire
    
    # Double-check installation
    aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
    aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")
    
    if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
        echo "Error: Failed to install .NET Aspire templates. Please install them manually using 'dotnet workload install aspire'"
        exit 1
    else
        echo ".NET Aspire templates installed successfully."
    fi
else
    echo ".NET Aspire templates are already installed."
fi

# Create top-level files to keep the solution self-contained (in current directory)
if [[ ! -f "${basepath}/.gitignore" ]]; then
    dotnet new gitignore
fi
if [[ ! -f "${basepath}/.editorconfig" ]]; then
    dotnet new editorconfig
fi

# Create solution and projects
dotnet new sln -n "${slnname}"
dotnet new aspire-apphost -n "${agentname}.Agent" -o "${basepath}/${agentname}.Agent"
dotnet new classlib -n "${agentname}.Agent.Cqrs" -o "${basepath}/${agentname}.Agent.Cqrs"
dotnet new classlib -n "${agentname}.Agent.Data" -o "${basepath}/${agentname}.Agent.Data"
\
# Ensure Data project targets .NET 9 explicitly
sed -i '' -e 's#<TargetFramework>.*</TargetFramework>#<TargetFramework>net9.0</TargetFramework>#' "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" || true
dotnet new aspire-servicedefaults -n "${agentname}.Y.Core" -o "${basepath}/${agentname}.Y.Core"
dotnet new webapi -n "${agentname}.Api.Endpoints" -o "${basepath}/${agentname}.Api.Endpoints"
dotnet new webapi -n "${agentname}.Mcp.Endpoints" -o "${basepath}/${agentname}.Mcp.Endpoints"
dotnet new web -n "${agentname}.Web.Endpoints" -o "${basepath}/${agentname}.Web.Endpoints"

# Add projects to solution
dotnet sln "${basepath}/${slnname}.sln" add "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
                                         "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
                                         "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" \
                                         "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
                                         "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Helper to add one or more NuGet packages to a specific project
add_packages() {
    local csproj="$1"; shift || true
    for spec in "$@"; do
        local name version
        if [[ "$spec" == *"@"* ]]; then
            name="${spec%@*}"
            version="${spec#*@}"
            dotnet add "$csproj" package "$name" --version "$version"
        else
            dotnet add "$csproj" package "$spec"
        fi
    done
}

# Add common NuGet packages
add_packages "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
    "MediatR@12.5.0"

# Data library NuGet packages
add_packages "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj" \
    "Microsoft.Extensions.Caching.Memory@9.0.6" \
    "Microsoft.Extensions.Configuration@9.0.6" \
    "MongoDB.Driver@3.4.0" \
    "System.Linq@4.3.0"

add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

# Helper to add project references
add_refs() {
    local target_csproj="$1"; shift || true
    for ref in "$@"; do
        dotnet add "$target_csproj" reference "$ref"
    done
}

# Add project references
add_refs "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
    "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"

add_refs "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

# Endpoints -> Data reference (for DI extension)
add_refs "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"
add_refs "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"

# Cqrs -> Data reference
add_refs "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
    "${basepath}/${agentname}.Agent.Data/${agentname}.Agent.Data.csproj"

# Setup centralized configuration by linking appsettings from Agent to Endpoint projects
echo "Setting up centralized configuration with linked appsettings files..."

# Function to apply XML edits to add linked appsettings
apply_linked_appsettings() {
    local project_path="$1"
    local project_file="$(basename "$project_path")"
    
    # Create a temporary file for the new content
    local temp_file="${project_path}.temp"
    
    # Read the project file
    cat "$project_path" > "$temp_file"
    
    # Check if the linked settings already exist (to avoid duplicates)
    if ! grep -q "Link=\"appsettings.json\"" "$temp_file"; then
        # Find the closing </Project> tag and insert our ItemGroup before it
        sed -i '' -e '/<\/Project>/i\
  <!-- Linked appsettings files from Agent project -->\
  <ItemGroup>\
    <Content Remove="appsettings.json" />\
    <Content Remove="appsettings.Development.json" />\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.json" Link="appsettings.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.Development.json" Link="appsettings.Development.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
  <\/ItemGroup>\
' "$temp_file"
    fi
    
    # Replace the original file
    mv "$temp_file" "$project_path"
}

# Apply linked appsettings to all endpoint projects
apply_linked_appsettings "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Seed Agent appsettings with Data configuration used by Data library
cat > "${basepath}/${agentname}.Agent/appsettings.json" << EOF
{
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft.AspNetCore": "Warning"
        }
    },
    "MongoDbSettings": {
        "StreamingDelayMilliseconds": 700,
        "ConnectionString": "mongodb://kabzda_user:KabzdaPass2025!@127.0.0.1:27017/${dbname}_db?authSource=${dbname}_db",
        "DatabaseName": "${dbname}_db"
    },
    "CachingSettings": {
        "LifetimeInMinutes": "27"
    },
    "FlashSettings": {
        "StoreDirectory": "FlashStore",
        "SerializerOptions": {
            "Encoding": "UTF-8",
            "WriteIndented": true,
            "UnsafeRelaxedJsonEscaping": true,
            "Encrypted": false
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent/appsettings.Development.json" << EOF
{
    "Logging": {
        "LogLevel": {
            "Default": "Information",
            "Microsoft.AspNetCore": "Warning"
        }
    },
    "MongoDbSettings": {
        "StreamingDelayMilliseconds": 700,
            "ConnectionString": "mongodb://kabzda_user:KabzdaPass2025!@127.0.0.1:27017/${dbname}_db?authSource=${dbname}_db",
            "DatabaseName": "${dbname}_db"
    },
    "CachingSettings": {
        "LifetimeInMinutes": "27"
    },
    "FlashSettings": {
        "StoreDirectory": "FlashStore",
        "SerializerOptions": {
            "Encoding": "UTF-8",
            "WriteIndented": true,
            "UnsafeRelaxedJsonEscaping": true,
            "Encrypted": false
        }
    }
}
EOF

# Generate Data library structure and source files
rm -f "${basepath}/${agentname}.Agent.Data/Class1.cs" || true
mkdir -p "${basepath}/${agentname}.Agent.Data/Contexts"
mkdir -p "${basepath}/${agentname}.Agent.Data/Defaults"
mkdir -p "${basepath}/${agentname}.Agent.Data/Models"
mkdir -p "${basepath}/${agentname}.Agent.Data/Repos"

cat > "${basepath}/${agentname}.Agent.Data/Injector.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Repos;

using Microsoft.Extensions.DependencyInjection;

namespace ${agentname}.Agent.Data;

public static class Injector
{
    public static void InjectDataServices(this IServiceCollection services)
    {
        services.AddMemoryCache();
        services.AddSingleton<MongoContext>();
        services.AddTransient<CacheContext>();
        services.AddTransient<FlashContext>();
        services.AddTransient<IRepositoryBuilder, RepositoryBuilder>();
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/MongoContext.cs" << EOF
using Microsoft.Extensions.Configuration;
using MongoDB.Driver;

namespace ${agentname}.Agent.Data.Contexts;

internal class MongoContext
{
    public IMongoDatabase Database { get; private set; }
    public int StreamingDelayMilliseconds { get; private set; }

    public MongoContext(IConfiguration configuration)
    {
        var database = GetDatabaseFrom(configuration);
        var conString = GetConnectionStringFrom(configuration);
        var streamingDelay = GetStreamingDelayFrom(configuration);

        Database = GetMongoClient(conString).GetDatabase(database);
        StreamingDelayMilliseconds = int.Parse(streamingDelay);
    }
    
    private static MongoClient GetMongoClient(string connectionString) => new (connectionString);

    private static string GetConnectionStringFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:ConnectionString"] ??
            throw new InvalidOperationException("MongoDbSettings:ConnectionString is not configured");
    
    private static string GetDatabaseFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:DatabaseName"]
            ?? throw new InvalidOperationException("MongoDbSettings:DatabaseName is not configured");
    
    private static string GetStreamingDelayFrom(IConfiguration configuration)
        => configuration["MongoDbSettings:StreamingDelayMilliseconds"]
            ?? throw new InvalidOperationException("MongoDbSettings:StreamingDelayMilliseconds is not configured");
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/CacheContext.cs" << EOF
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Configuration;

namespace ${agentname}.Agent.Data.Contexts;

internal class CacheContext(
    IMemoryCache memoryCache,
    IConfiguration configuration)
{
    public (bool succeeded, T? entity) GetEntity<T> (string key) where T:class 
        => (memoryCache.TryGetValue<T>(key, out var entity), entity);

    public void AddEntity<T>(string key, T entity) where T : class
    {
        var lifeTime = GetCachingLifetime(configuration);
        memoryCache.Set(key, entity, TimeSpan.FromMinutes(lifeTime));
    }

    public void RemoveEntity<T>(string key) where T: class => memoryCache.Remove(key);

    private static double GetCachingLifetime(IConfiguration configuration)
    {
        var lifetimeConfig = configuration["CachingSettings:LifetimeInMinutes"]
            ?? throw new InvalidOperationException("CachingSettings.LifetimeInMinutes is not configured");
        
        return double.Parse(lifetimeConfig);
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Contexts/FlashContext.cs" << EOF
using System.Text;
using System.Text.Json;
using System.Text.Encodings.Web;
using Microsoft.Extensions.Configuration;

namespace ${agentname}.Agent.Data.Contexts;

internal class FlashContext(
    IConfiguration configuration)
{
    private readonly IConfiguration _configuration = configuration;
    private readonly SemaphoreSlim _semaphore = new(1, 1);

    public Task<List<T>> ReadFromJsonCollectionAsync<T>(string collectionPath)
        => ExecuteWithLockAsync(() => DeserializeFromFileAsync<List<T>>(collectionPath));

    public Task WriteToJsonCollectionAsync<T>(string collectionPath, List<T> data)
        => ExecuteWithLockAsync(() => SerializeToFileAsync(collectionPath, data));

    public Task CheckCollectionAsync<T>(string collectionPath)
    {
        EnsureFlashStoreDirectoryExists();
        return ExecuteWithLockAsync(async () =>
        {
            if (!FlashStoreCollectionExist(collectionPath))
            {
                await SerializeToFileAsync(collectionPath, new List<T>());
            }
        });
    }

    private void EnsureFlashStoreDirectoryExists()
    {
        var flashDir = GetFlashStoreSettingsDirectory();
        if (!Directory.Exists(flashDir))
        {
            Directory.CreateDirectory(flashDir);
        }
    }

    private bool FlashStoreCollectionExist(string name)
        => File.Exists(GetCollectionPath(name));

    private string GetFlashStoreSettingsDirectory()
        => _configuration["FlashSettings:StoreDirectory"] ??
            throw new InvalidOperationException("FlashSettings:StoreDirectory is not configured");

    private string GetCollectionPath(string name)
    {
        var flashDir = GetFlashStoreSettingsDirectory();
        return $"{flashDir.TrimEnd('/')}/{name.TrimStart('/')}";
    }

    private async Task<T> ExecuteWithLockAsync<T>(Func<Task<T>> action)
    {
        await _semaphore.WaitAsync();
        try
        {
            return await action();
        }
        finally
        {
            _semaphore.Release();
        }
    }

    private Task<bool> ExecuteWithLockAsync(Func<Task> action) =>
        ExecuteWithLockAsync(async () => { await action(); return true; });

    private Task<T> DeserializeFromFileAsync<T>(string filePath) =>
        File.ReadAllTextAsync(GetCollectionPath(filePath))
            .ContinueWith(t => JsonSerializer.Deserialize<T>(t.Result) ??
                throw new NullReferenceException("Deserialization result is null"));

    private async Task SerializeToFileAsync<T>(string filePath, T data)
    {
        var encodingName = _configuration["FlashSettings:SerializerOptions:Encoding"] ?? 
            throw new InvalidOperationException("FlashSettings:SerializerOptions:Encoding is not configured");
        string json = JsonSerializer.Serialize(data, GetSerializerOptions());
            await File.WriteAllTextAsync(GetCollectionPath(filePath), json,
                Encoding.GetEncoding(encodingName) ?? Encoding.Default);
    }

    private JsonSerializerOptions GetSerializerOptions()
    {
        var writeIndentedFlag = _configuration["FlashSettings:SerializerOptions:WriteIndented"] ??
            throw new InvalidOperationException("FlashSettings:SerializerOptions:WriteIndented is not configured");

        var unsafeEscapingFlag = _configuration["FlashSettings:SerializerOptions:UnsafeRelaxedJsonEscaping"] ??
            throw new InvalidOperationException("FlashSettings:SerializerOptions:UnsafeRelaxedJsonEscaping is not configured");

        return new()
        {
            WriteIndented = bool.Parse(writeIndentedFlag),
            Encoder = bool.Parse(unsafeEscapingFlag)
                ? JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                : JavaScriptEncoder.Default
        };
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Defaults/Attributes.cs" << EOF
namespace ${agentname}.Agent.Data.Defaults;

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Struct)]
public class CollectionNameAttribute(string name) : Attribute
{
    public string EntityName { get; init; } = name;
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Defaults/Extensions.cs" << EOF
using System.Reflection;

namespace ${agentname}.Agent.Data.Defaults;

internal static class CollectionNameAttributeExtensions
{
    public static string GetCollectionName(this Type entity)
    {
        try
        {
            return entity!.GetCustomAttribute<CollectionNameAttribute>()!.EntityName;
        }
        catch (Exception)
        {
            return $"{entity.Name}s";
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/EntityBase.cs" << EOF
using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ${agentname}.Agent.Data.Models;

public abstract class EntityBase<TId>
{
    [BsonId]
    [BsonRepresentation(BsonType.String)]
    public required TId Id { get; set; }

    [BsonRepresentation(BsonType.String)]
    public required DateTime CreatedAt { get; set; }

    public EntityBase()
    {
        CreatedAt = DateTime.UtcNow;
    }
}

public abstract class GuidEntity : EntityBase<Guid>
{
    [BsonRepresentation(BsonType.String)]
    public required DateTime UpdatedAt { get; set; }
    
    public GuidEntity() : base()
    {
        Id = Guid.NewGuid();
        UpdatedAt = CreatedAt;
    }

    public GuidEntity(Guid id) : base()
    {
        Id = id;
        UpdatedAt = CreatedAt;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/PagedList.cs" << EOF
using System.Collections;

namespace ${agentname}.Agent.Data.Models;

public class PagedList<TEntity>(
    IEnumerable<TEntity> items,
    int count,
    int pageNumber,
    int pageSize) : IReadOnlyList<TEntity>
{
    private readonly IList<TEntity> _subset = items as IList<TEntity> ?? [..items];

    public int PageNumber { get; } = pageNumber;
    public int TotalPages { get; } = (int)Math.Ceiling(count / (double)pageSize);

    public int Count { get; } = count;

    public bool IsFirstPage => PageNumber == 1;
    public bool IsLastPage => PageNumber == TotalPages;
    public bool HasNextPage => PageNumber < TotalPages;
    public bool HasPreviousPage => PageNumber > 1;


    public TEntity this[int index] => _subset[index];
    public IEnumerator<TEntity> GetEnumerator() => _subset.GetEnumerator();
    IEnumerator IEnumerable.GetEnumerator() => _subset.GetEnumerator();
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Models/TimespanFilter.cs" << EOF
namespace ${agentname}.Agent.Data.Models;

public record TimespanFilter
{
    public DateTime From { get; set; }
    public DateTime To {get; set; }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/Repository.cs" << EOF
namespace ${agentname}.Agent.Data.Repos;

public interface IRepository<TEntity> where TEntity : class
{
    Task<TEntity?> GetByIdAsync(Guid id);
    Task<TEntity> InsertAsync(TEntity entity);
    Task<TEntity> UpdateAsync(TEntity entity);
    ValueTask<bool> DeleteAsync(TEntity entity);
    ValueTask<bool> DeleteManyAsync(List<TEntity> entities);
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/RepositoryBuilder.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface IRepositoryBuilder
{
    ICacheRepository<TEntity> CreateCacheRepository<TEntity>() where TEntity : GuidEntity;
    IFlashRepository<TEntity> CreateFlashRepository<TEntity>() where TEntity : GuidEntity;
    IMongoRepository<TEntity> CreateMongoRepository<TEntity>() where TEntity : GuidEntity;
}

internal class RepositoryBuilder(
    CacheContext cacheContext,
    FlashContext flashContext,
    MongoContext mongoContext)
    : IRepositoryBuilder
{
    public ICacheRepository<TEntity> CreateCacheRepository<TEntity>()
        where TEntity : GuidEntity => new CacheRepository<TEntity>(cacheContext);

    public IFlashRepository<TEntity> CreateFlashRepository<TEntity>()
        where TEntity : GuidEntity => new FlashRepository<TEntity>(flashContext);

    public IMongoRepository<TEntity> CreateMongoRepository<TEntity>()
        where TEntity : GuidEntity => new MongoRepository<TEntity>(mongoContext);
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/CacheRepository.cs" << EOF
using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface ICacheRepository<TEntity>: IRepository<TEntity> where TEntity : class { }

internal class CacheRepository<TEntity>(CacheContext context)
    : ICacheRepository<TEntity> where TEntity : GuidEntity
{
    public Task<TEntity?> GetByIdAsync(Guid id)
    {
        var (succeeded, entity) = context.GetEntity<TEntity>(id.ToString());

        return succeeded ? Task.FromResult(entity) : Task.FromResult(default(TEntity));
    }

    public Task<TEntity> InsertAsync(TEntity entity)
    {
        context.AddEntity(entity.Id.ToString(), entity);
        return Task.FromResult(entity);
    }

    public Task<TEntity> UpdateAsync(TEntity entity)
    {
        context.AddEntity(entity.Id.ToString(), entity);
        return Task.FromResult(entity);
    }

    public ValueTask<bool> DeleteAsync(TEntity entity)
    {
        context.RemoveEntity<TEntity>(entity.Id.ToString());
        return ValueTask.FromResult(true);
    }

    public ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        throw new NotImplementedException();
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/FlashRepository.cs" << EOF
using System.Linq.Expressions;

using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Models;

namespace ${agentname}.Agent.Data.Repos;

public interface IFlashRepository<TEntity>: IRepository<TEntity> where TEntity : class
{
    Task<List<TEntity>> ToListAsync();
    Task<List<TEntity>> ToFilteredListAsync(Expression<Func<TEntity, bool>> filteringField);
    Task<TEntity?> GetFilteredEntity(Expression<Func<TEntity, bool>> filteringField);
}

internal class FlashRepository<TEntity>(FlashContext context)
    : IFlashRepository<TEntity> where TEntity : GuidEntity
{
    private const string CollectionNameFormat = "{0}sCollection.json";
    private const int FirstValidIndex = 0;
    
    private readonly FlashContext _context = context;

    public async Task<List<TEntity>> ToListAsync()
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        return [.. await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath)];
    }

    public async Task<List<TEntity>> ToFilteredListAsync(Expression<Func<TEntity, bool>> filteringField)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return [.. collection.AsQueryable().Where(filteringField)];
    }

    public async Task<TEntity?> GetFilteredEntity(Expression<Func<TEntity, bool>> filteringField)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return collection.AsQueryable().FirstOrDefault(filteringField);
    }

    public async Task<TEntity?> GetByIdAsync(Guid id)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        return collection.FirstOrDefault(e => e.Id == id);
    }

    public async Task<TEntity> InsertAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        collection.Add(entity);
        await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        return entity;
    }

    public async Task<TEntity> UpdateAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        var index = collection.FindIndex(e => e.Id == entity.Id);
        if (index >= FirstValidIndex)
        {
            collection[index] = entity;
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        }
        return entity;
    }

    public async ValueTask<bool> DeleteAsync(TEntity entity)
    {
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        var index = collection.FindIndex(e => e.Id == entity.Id);
        if (index >= FirstValidIndex)
        {
            collection.RemoveAt(index);
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
            return true;
        }
        return false;
    }

    public async ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        var removed = false;
        var collectionPath = await GetCollectionPath(typeof(TEntity));
        var collection = await _context.ReadFromJsonCollectionAsync<TEntity>(collectionPath);
        foreach (var entity in entities)
        {
            removed |= collection.Remove(entity);
        }
        if (removed)
        {
            await _context.WriteToJsonCollectionAsync(collectionPath, collection);
        }
        return removed;
    }

    private async ValueTask<string> GetCollectionPath(Type entityType)
    {
        var collectionPath = string.Format(CollectionNameFormat, entityType.Name);
        await _context.CheckCollectionAsync<List<Type>>(collectionPath);
        return collectionPath;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Data/Repos/MongoRepository.cs" << EOF
using System.Linq.Expressions;
using System.Runtime.CompilerServices;

using ${agentname}.Agent.Data.Contexts;
using ${agentname}.Agent.Data.Defaults;
using ${agentname}.Agent.Data.Models;

using MongoDB.Driver;
using MongoDB.Driver.Linq;

namespace ${agentname}.Agent.Data.Repos;

public interface IMongoRepository<TEntity> : IRepository<TEntity> where TEntity : class
{
    Task<TEntity> GetFilteredEntityAsync(Expression<Func<TEntity, bool>> predicate);
    Task<PagedList<TEntity>> GetPagedListAsync<TKey>(Expression<Func<TEntity, bool>> filter, Expression<Func<TEntity, TKey>> sorter, int page, int pageSize, bool asc);
    Task<List<TEntity>> GetFilteredSortedListAsync<TKey>(Expression<Func<TEntity, bool>> filter, Expression<Func<TEntity, TKey>> sorter, bool asc);
    Task<List<TEntity>> GetFilteredListAsync(Expression<Func<TEntity, bool>> filter);
    IAsyncEnumerable<TEntity> StreamCollectionItemsAsync(CancellationToken token, TimespanFilter? filter = default);
}

internal class MongoRepository<TEntity>(MongoContext context)
    : IMongoRepository<TEntity> where TEntity : GuidEntity
{
    private const int MaxRetries = 3;
    private const int BatchSize = 100;
    private const int SingleItemCount = 1;
    private const int EmptyCollectionCount = 0;
    private const int PageIndexOffset = 1;
    private const int RetryDelayBaseExponent = 2;
    private readonly MongoContext _context = context;
    protected IMongoCollection<TEntity> DbSet
        => _context.Database.GetCollection<TEntity>(
            typeof(TEntity).GetCollectionName());

    #region CRUD from default repository
    public async Task<TEntity?> GetByIdAsync(Guid id)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(e => e.Id == id);
    }
    public async Task<TEntity?> GetByIdAsync(string id)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(e => e.Id.ToString() == id);
    }
    public async Task<TEntity> InsertAsync(TEntity entity)
    {
        await DbSet.InsertOneAsync(entity);
        return entity;
    }
    public async Task<TEntity> UpdateAsync(TEntity entity)
    {
        await DbSet.ReplaceOneAsync(e => e.Id == entity.Id, entity);
        return entity;
    }
    public async ValueTask<bool> DeleteAsync(TEntity entity)
    {
        var result = await DbSet.DeleteOneAsync(e => e.Id == entity.Id);
        return result.DeletedCount == SingleItemCount;
    }
    public async ValueTask<bool> DeleteManyAsync(List<TEntity> entities)
    {
        var result = await DbSet.DeleteManyAsync(e => entities.Contains(e));
        return result.DeletedCount == entities.Count;
    }
    #endregion
    #region From IMongoRepository
    public async Task<TEntity> GetFilteredEntityAsync(Expression<Func<TEntity, bool>> predicate)
    {
        return await DbSet.AsQueryable().FirstOrDefaultAsync(predicate);
    }
    public async Task<List<TEntity>> GetFilteredListAsync(Expression<Func<TEntity, bool>> filter)
    {
        return await DbSet.AsQueryable().Where(filter).ToListAsync();
    }

    public async Task<PagedList<TEntity>> GetPagedListAsync<TKey>(
        Expression<Func<TEntity, bool>> filter,
        Expression<Func<TEntity, TKey>> sorter,
        int page, int pageSize, bool asc)
    {
        List<TEntity> results;
        var queryable = DbSet.AsQueryable();

        results = asc
            ? await queryable.Where(filter).OrderBy(sorter).Skip((page - PageIndexOffset) * pageSize).Take(pageSize).ToListAsync()
            : await queryable.Where(filter).OrderByDescending(sorter).Skip((page - PageIndexOffset) * pageSize).Take(pageSize).ToListAsync();
        return new PagedList<TEntity>(results, queryable.Where(filter).Count(), page, pageSize);
    }

    public async Task<List<TEntity>> GetFilteredSortedListAsync<TKey>(
        Expression<Func<TEntity, bool>> filter,
        Expression<Func<TEntity, TKey>> sorter,
        bool asc)
    {
        List<TEntity> results;
        var queryable = DbSet.AsQueryable();

        results = asc
            ? await queryable.Where(filter).OrderBy(sorter).ToListAsync()
            : await queryable.Where(filter).OrderByDescending(sorter).ToListAsync();
        return results;
    }
    #endregion
    #region Additional Data Streaming Methods
    public async IAsyncEnumerable<TEntity> StreamCollectionItemsAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default,
        TimespanFilter? timespan = default)
    {
        Guid? lastProcessedId = null;

        while (true)
        {
            var batchItems = await FetchBatchItemsAsync(lastProcessedId, timespan, cancellationToken);

            if (batchItems == null || batchItems.Count == EmptyCollectionCount)
            {
                yield break;
            }

            foreach (var collectionItem in batchItems)
            {
                if (cancellationToken.IsCancellationRequested)
                {
                    yield break;
                }

                lastProcessedId = collectionItem.Id;
                await Task.Delay(_context.StreamingDelayMilliseconds, cancellationToken);

                yield return collectionItem;
            }
        }
    }

    private async Task<List<TEntity>?> FetchBatchItemsAsync(
        Guid? lastProcessedId,
        TimespanFilter? timespan,
        CancellationToken cancellationToken)
    {
        var options = CreateFindOptions();
        var filter = timespan is null
            ? CreateFilter(lastProcessedId)
            : CreateFilter(lastProcessedId, timespan);

        for (int attempt = 0; attempt < MaxRetries; attempt++)
        {
            try
            {
                using var cursor = await DbSet.FindAsync(filter, options, cancellationToken);
                return await cursor.ToListAsync(cancellationToken);
            }
            catch (MongoException)
            {
                if (attempt == MaxRetries - SingleItemCount)
                {
                    throw;
                }

                await Task.Delay(TimeSpan.FromSeconds(Math.Pow(RetryDelayBaseExponent, attempt)), cancellationToken);
            }
        }

        return null;
    }

    private static FilterDefinition<TEntity> CreateFilter(Guid? lastProcessedId)
    {
        var baseFilter = Builders<TEntity>.Filter.Empty;
        return lastProcessedId.HasValue
            ? Builders<TEntity>.Filter.Gt(x => x.Id, lastProcessedId.Value)
            : baseFilter;
    }

    private static FilterDefinition<TEntity> CreateFilter(Guid? lastProcessedId, TimespanFilter timespan)
    {
        var baseFilter = Builders<TEntity>.Filter.And(
            Builders<TEntity>.Filter.Gte(x => x.CreatedAt, timespan.From),
            Builders<TEntity>.Filter.Lte(x => x.CreatedAt, timespan.To)
        );

        if (lastProcessedId.HasValue)
        {
            baseFilter = Builders<TEntity>.Filter.And(
                baseFilter,
                Builders<TEntity>.Filter.Gt(x => x.Id, lastProcessedId.Value)
            );
        }

        return baseFilter;
    }

    private static FindOptions<TEntity> CreateFindOptions()
    {
        return new FindOptions<TEntity>
        {
            BatchSize = BatchSize,
            Sort = Builders<TEntity>.Sort.Ascending(x => x.Id)
        };
    }
    #endregion
}
EOF

# Create basic CQRS structure
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Commands"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Queries"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Models"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Handlers"

# Create example Command and Query files
cat > "${basepath}/${agentname}.Agent.Cqrs/Commands/ExampleCommand.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Commands
{
    public class ExampleCommand : IRequest<bool>
    {
        public string Data { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Queries/ExampleQuery.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Queries
{
    public class ExampleQuery : IRequest<string>
    {
        public string Id { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleCommandHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Commands;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleCommandHandler : IRequestHandler<ExampleCommand, bool>
    {
        public Task<bool> Handle(ExampleCommand request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(true);
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleQueryHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleQueryHandler : IRequestHandler<ExampleQuery, string>
    {
        public Task<string> Handle(ExampleQuery request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(\$"Response for ID: {request.Id}");
        }
    }
}
EOF

# Create sample controllers
mkdir -p "${basepath}/${agentname}.Api.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Api.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Api.Endpoints.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExampleController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ExampleController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

mkdir -p "${basepath}/${agentname}.Mcp.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Mcp.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Mcp.Endpoints.Controllers
{
    [ApiController]
    [Route("mcp/[controller]")]
    public class ChatController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ChatController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

# Update Program.cs files to include MediatR and Swagger
cat > "${basepath}/${agentname}.Api.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Mcp.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Web.Endpoints/Program.cs" << EOF
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

var app = builder.Build();

// Add static files middleware for Assets/Files directory
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(
        Path.Combine(Directory.GetCurrentDirectory(), "Assets", "Files")),
    RequestPath = "/Files"
});

app.MapGet("/", async (HttpContext httpContext) =>
{
    var contentPath = Path.Combine("Assets", $"index.html");
    if (!File.Exists(contentPath))
    {
        return Results.NotFound($"File not found: {contentPath}");
    }

    var content = await File.ReadAllTextAsync(contentPath);
    return Results.Content(content, "text/html");
});

app.Run();
EOF

# Create Assets directory and index.html for Web.Endpoints
mkdir -p "${basepath}/${agentname}.Web.Endpoints/Assets/Files"

# Create index.html
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Web Agents Template | BIZMASTER AGENCY</title>
    <!-- Material Design Icons -->
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
    <!-- Material Design Web Components -->
    <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,500" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Roboto', sans-serif;
        }
        
        body {
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 2rem;
        }
        
        .container {
            max-width: 800px;
            width: 100%;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            margin: 0 auto;
            transition: all 0.3s ease;
        }
        
        .header {
            background-color: #2196F3;
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .header h1 {
            font-weight: 400;
            margin-bottom: 0.5rem;
            font-size: 2rem;
        }
        
        .header p {
            font-weight: 300;
            opacity: 0.9;
        }
        
        .content {
            padding: 2rem;
        }
        
        .feature {
            display: flex;
            align-items: center;
            margin-bottom: 1.5rem;
        }
        
        .feature-icon {
            background-color: #2196F3;
            color: white;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 1rem;
            flex-shrink: 0;
            font-size: 1.8rem; /* Increased font size for emojis */
        }
        
        .feature-text h3 {
            font-weight: 500;
            margin-bottom: 0.3rem;
            color: #1976D2;
        }
        
        .footer {
            background-color: #f9f9f9;
            padding: 1.5rem 2rem;
            text-align: center;
            border-top: 1px solid #eee;
        }
        
        .footer a {
            color: #2196F3;
            text-decoration: none;
            transition: color 0.3s;
        }
        
        .footer a:hover {
            color: #0D47A1;
            text-decoration: underline;
        }
        
        .cta-button {
            background-color: #2196F3;
            color: white;
            border: none;
            padding: 0.8rem 1.5rem;
            font-size: 1rem;
            border-radius: 4px;
            cursor: pointer;
            margin-top: 1.5rem;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
            transition: all 0.3s ease;
            display: inline-block;
            text-decoration: none;
        }
        
        .cta-button:hover {
            background-color: #1976D2;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
            transform: translateY(-2px);
        }
        
        /* Responsive design */
        @media (max-width: 768px) {
            .header {
                padding: 1.5rem;
            }
            
            .header h1 {
                font-size: 1.8rem;
            }
            
            .content {
                padding: 1.5rem;
            }
            
            .feature {
                flex-direction: column;
                text-align: center;
            }
            
            .feature-icon {
                margin-right: 0;
                margin-bottom: 1rem;
            }
        }
        
        @media (max-width: 480px) {
            body {
                padding: 1rem;
            }
            
            .header {
                padding: 1.2rem;
            }
            
            .header h1 {
                font-size: 1.5rem;
            }
            
            .content {
                padding: 1.2rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AI Web Agents Starter Kit</h1>
            <p>A comprehensive framework for developing intelligent web agents</p>
        </div>
        
        <div class="content">
            <div class="feature">
                <div class="feature-icon">
                    <span>👨‍💻</span>
                </div>
                <div class="feature-text">
                    <h3>Developer-Friendly</h3>
                    <p>Build powerful AI web agents with our streamlined template designed for maximum productivity and efficiency.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🤖</span>
                </div>
                <div class="feature-text">
                    <h3>AI-Powered</h3>
                    <p>Leverage cutting-edge artificial intelligence capabilities to create responsive and intelligent web agents.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🔌</span>
                </div>
                <div class="feature-text">
                    <h3>Easy Integration</h3>
                    <p>Seamlessly integrate with existing systems using our well-designed API endpoints and Model Context Protocol.</p>
                </div>
            </div>
            
            <div style="text-align: center; margin-top: 2rem;">
                <a href="https://www.bizmaster.agency" class="cta-button">Learn More</a>
            </div>
        </div>
        
        <div class="footer">
            <p>Developed by <a href="https://www.bizmaster.agency" target="_blank">BIZMASTER AGENCY</a> &copy; 2025</p>
        </div>
    </div>
</body>
</html>
EOF

# Create sample DID file in Assets/Files
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/Files/did.txt" << EOF
some did structure placed here
EOF

# Update Agent's Program.cs to properly register services
cat > "${basepath}/${agentname}.Agent/AppHost.cs" << EOF
var builder = DistributedApplication.CreateBuilder(args);

var apiService = builder.AddProject<Projects.${agentname}_Api_Endpoints>("api-endpoints");
var mcpService = builder.AddProject<Projects.${agentname}_Mcp_Endpoints>("mcp-endpoints");
var webService = builder.AddProject<Projects.${agentname}_Web_Endpoints>("web-endpoints");

builder.Build().Run();
EOF

# Create a README.md with documentation about the project structure
cat > "${basepath}/README.md" << EOF
# ${agentname} Project

This project was generated using the agent_starter_kit.sh script.

## Project Structure

- **${agentname}.Agent**: Aspire app host that coordinates all services
- **${agentname}.Agent.Cqrs**: Class library containing CQRS commands, queries, and handlers
- **${agentname}.Agent.Data**: Data access library (Mongo, in-memory cache, flash storage) with repositories and models
- **${agentname}.Y.Core**: Aspire service defaults for configuration
- **${agentname}.Api.Endpoints**: Web API for external API endpoints
- **${agentname}.Mcp.Endpoints**: Web API for Model Context Protocol endpoints
- **${agentname}.Web.Endpoints**: Web application for UI

## Getting Started

1. Build the solution: \`dotnet build\`
2. Run the solution: \`dotnet run --project ${agentname}.Agent/${agentname}.Agent.csproj\`

## Dependencies

- .NET 9.0+
- .NET Aspire
- MediatR for CQRS
- FluentValidation
- Swashbuckle for OpenAPI/Swagger

EOF

# Add Healthchecks
add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"
add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"

# Restore, build, and watch
dotnet restore "${basepath}/${slnname}.sln"
dotnet build "${basepath}/${slnname}.sln"
dotnet watch run --project "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj"

echo "All processes completed successfully."
echo "Project structure has been set up with CQRS pattern, example controllers, and MediatR integration."